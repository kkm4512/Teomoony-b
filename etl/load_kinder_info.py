# -*- coding: utf-8 -*-
"""유치원 공시 상세 적재 — 유치원알리미 OpenAPI 항목별 원문  2026-10-24  (deploy/sql/338)

  py load_kinder_info.py                 load_kinder.py 와 같은 시군구(단지가 있는 곳)
  py load_kinder_info.py --sgg 11290     고른 구만
  py load_kinder_info.py --probe         한 구 · 한 항목만

★ 원문 한 줄을 그대로 raw_json 에 둔다(칸 정의는 유치원알리미 OPENAPI 각 항목 페이지). 계산하지 않는다.
★ 래퍼는 kinderInfo. 구조가 바뀌면 받은 키를 찍고 멈춘다.
★ 키는 .env KINDER_KEY — 화면 · 로그에 안 찍는다.
"""
import argparse, json, os, sys, time
import requests, pymssql

HERE = os.path.dirname(os.path.abspath(__file__))
ENV  = os.path.join(HERE, "..", ".env")
BASE = "https://e-childschoolinfo.moe.go.kr/api/notice/{}.do"
ITEMS = ["basicInfo2", "building", "classArea", "teachersInfo", "yearOfWork", "lessonDay", "schoolBus",
         "safetyEdu", "schoolMeal", "environmentHygiene", "afterSchoolPresent"]


def load_env(p):
    d = {}
    for line in open(p, encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line: continue
        k, v = line.split("=", 1); d[k.strip()] = v.strip()
    return d


def fetch(key, item, sgg):
    last = None
    for a in range(4):
        try:
            r = requests.get(BASE.format(item), params={"key": key, "sidoCode": sgg[:2], "sggCode": sgg}, timeout=60)
            d = r.json()
            if "kinderInfo" not in d:
                if str(d.get("status", "")).upper() == "SUCCESS": return []
                sys.exit(f"구조가 바뀜({item}): {list(d.keys())}")
            return d.get("kinderInfo") or []
        except (requests.RequestException, ValueError) as e:
            last = e; time.sleep(2 + a * 3)
    print(f"   실패 {item} {sgg}: {last}"); return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sgg", nargs="*")
    ap.add_argument("--probe", action="store_true")
    a = ap.parse_args()
    env = load_env(ENV)
    key = env.get("KINDER_KEY", "").strip()
    if not key: sys.exit(".env 에 KINDER_KEY 가 없습니다")
    conn = pymssql.connect(server=env.get("DB_HOST", "127.0.0.1"), port=int(env.get("DB_PORT", 11433)),
                           user=env.get("DB_USER", "sa"), password=env.get("DB_PASSWORD", ""),
                           database=env.get("DB_NAME", "Teomoony"), charset="UTF-8", autocommit=False)
    cur = conn.cursor()
    if a.sgg: sggs = list(a.sgg)
    else:
        cur.execute("SELECT DISTINCT sigungu_cd FROM gold.complex WHERE is_active = 1 AND sigungu_cd IS NOT NULL ORDER BY sigungu_cd")
        sggs = [r[0] for r in cur.fetchall()]
    items = ITEMS[:1] if a.probe else ITEMS
    if a.probe: sggs = sggs[:1]
    print(f"시군구 {len(sggs)}개 × 항목 {len(items)}개", flush=True)
    n = 0; 실패 = 0
    for sgg in sggs:
        for item in items:
            L = fetch(key, item, sgg)
            if L is None: 실패 += 1; continue
            for d in L:
                code = d.get("kindercode") or d.get("kinderCode")
                if not code: continue
                d = {k: v for k, v in d.items() if k not in ("key", "page")}
                cur.execute("DELETE FROM silver.kinder_info WHERE kinder_cd = %s AND item = %s", (code, item))
                cur.execute("INSERT INTO silver.kinder_info (kinder_cd, item, pbnt_tmng, raw_json, collected_at) VALUES (%s,%s,%s,%s, CONVERT(date, SYSDATETIME()))",
                            (code, item, str(d.get("pbnttmng") or d.get("pbntTmng") or "") or None, json.dumps(d, ensure_ascii=False)))
                n += 1
            conn.commit()
        print(f"  {sgg}  누적 {n:,}", flush=True)
    print(f"\n유치원 공시 상세 {n:,}줄 · 실패 {실패}")
    conn.close()


if __name__ == "__main__":
    main()
