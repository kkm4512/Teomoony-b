# -*- coding: utf-8 -*-
"""load_hira_open - 심평원 요양기관 개설 현황(표시과목) 적재  2026-10-22

  py load_hira_open.py              전국 (2025-12-31 기준 파일)
  py load_hira_open.py --probe      받기만, 건수

★ 출처: odcloud 15051057 (파일데이터 API). 연 1회 갱신 — 새 해 파일이 올라오면 UDDI 와 기준일만 바꾼다.
★ 다 받았을 때만(받은 수 = totalCount) 넣는다. 덜 받고 넣으면 '표시과목 없음' 이 거짓말이 된다.
"""
import argparse, io, json, os, sys, time
import urllib.parse, urllib.request
import pymssql

HERE = os.path.dirname(os.path.abspath(__file__))
ENV  = os.path.join(HERE, "..", ".env")
UDDI = "uddi:466a7aa3-61fd-4f73-bc84-9786b7d6e1b4"   # 건강보험심사평가원_요양기관 개설 현황_20251231
기준일 = "20251231"
URL  = f"https://api.odcloud.kr/api/15051057/v1/{UDDI}"


def env():
    d = {}
    for line in io.open(ENV, encoding="utf-8-sig"):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1); d[k.strip()] = v.strip()
    return d


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--probe", action="store_true"); a = ap.parse_args()
    e = env(); key = e.get("DATA_GO_KR_KEY", "")
    if not key: sys.exit(".env 의 DATA_GO_KR_KEY 가 비어 있습니다")
    K = key if "%" in key else urllib.parse.quote(key)
    out, page, total = [], 1, None
    while True:
        u = URL + "?serviceKey=" + K + "&" + urllib.parse.urlencode({"page": page, "perPage": 1000, "returnType": "JSON"})
        for t in range(3):
            try:
                with urllib.request.urlopen(u, timeout=60) as r:
                    j = json.loads(r.read().decode("utf-8")); break
            except Exception as ex:
                if t == 2: raise RuntimeError(f"page {page}: {str(ex)[:120]}")
                time.sleep(2 * (t + 1))
        total = int(j.get("totalCount") or 0); d = j.get("data") or []
        out += d
        if page % 20 == 0: print(f"  {len(out):,}/{total:,}", flush=True)
        if len(out) >= total or not d: break
        page += 1; time.sleep(0.2)
    print(f"받음 {len(out):,} / {total:,}", flush=True)
    if len(out) < total: sys.exit("다 받지 못해서 넣지 않습니다")
    if a.probe: return

    conn = pymssql.connect(server=e.get("DB_HOST", "127.0.0.1"), port=int(e.get("DB_PORT", 11433)),
                           user=e.get("DB_USER", "sa"), password=e.get("DB_PASSWORD", ""),
                           database=e.get("DB_NAME", "Teomoony"), charset="UTF-8", autocommit=False)
    # ★ 2026-10-22 실측: 요양기호 하나가 **519곳**에 똑같이 붙어 있다(아직 기호가 안 매겨진 곳의 자리표시 값으로 보인다).
    #   그대로 넣으면 519곳이 한 줄로 뭉쳐 마지막 값이 이긴다 — 조용히 틀린 값. 두 번 이상 나오는 기호는 **넣지 않는다**.
    from collections import Counter
    셈 = Counter(x.get("암호화된요양기호") for x in out)
    겹침 = {y for y, c in 셈.items() if y and c > 1}
    if 겹침: print(f"  같은 요양기호가 여러 곳에 붙은 것 {len(겹침)}개 · {sum(셈[y] for y in 겹침):,}행 — 넣지 않음", flush=True)
    cur = conn.cursor(); n = 0
    for x in out:
        y = x.get("암호화된요양기호")
        if not y or y in 겹침: continue
        v = (기준일, x.get("요양기관명"), x.get("요양종별"), x.get("표시과목명"), x.get("개설일자"),
             x.get("시도명"), x.get("시군구명"), x.get("도로명주소"))
        cur.execute("""UPDATE silver.hira_open SET 기준일=%s, 요양기관명=%s, 요양종별=%s, 표시과목=%s, 개설일자=%s,
                         시도명=%s, 시군구명=%s, 도로명주소=%s, loaded_at=SYSDATETIME() WHERE ykiho=%s""", v + (y,))
        if cur.rowcount == 0:
            cur.execute("""INSERT INTO silver.hira_open (기준일, 요양기관명, 요양종별, 표시과목, 개설일자, 시도명, 시군구명, 도로명주소, ykiho)
                           VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)""", v + (y,))
        n += 1
        if n % 10000 == 0: conn.commit(); print(f"  넣음 {n:,}", flush=True)
    conn.commit()
    cur.execute("""SELECT 전체 = COUNT(*), 이어짐 = SUM(CASE WHEN h.ykiho IS NOT NULL THEN 1 ELSE 0 END)
                     FROM silver.hira_inst h0 LEFT JOIN silver.hira_open h ON h.ykiho = h0.ykiho WHERE h0.is_current = 1""")
    r = cur.fetchone()
    print(f"넣음 {n:,} · 심평원 목록 {r[0]:,} 중 표시과목 이어짐 {r[1]:,}", flush=True)
    conn.close()


if __name__ == "__main__":
    main()
