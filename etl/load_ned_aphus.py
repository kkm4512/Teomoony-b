# -*- coding: utf-8 -*-
"""load_ned_aphus - VWorld NED 공동주택가격(getApartHousingPriceAttr) → silver.ned_aphus_price  (2026-10-22, deploy/sql/306)
  py load_ned_aphus.py --workers 4            연립·다세대 호가 있는 필지 전부(서울·안양) — 이어받기
  py load_ned_aphus.py --max-min 300          5시간 넘으면 멈춤(다음에 이어받기)
★ 키 = .env VWORLD_NED_KEY(없으면 VWORLD_KEY) — 토지특성·토지이동이력이 VWORLD_KEY 를 쓰므로 나눠 쓴다. 화면·로그에 안 찍는다.
★ 한 필지에 모든 해(2006~)가 온다(stdrYear 를 안 주면). 원문 그대로. 이력 0건도 '다 받음'. 실패한 필지는 done 에 안 적는다.
"""
import argparse, io, json, os, sys, time, urllib.parse, urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
HERE = os.path.dirname(os.path.abspath(__file__)); ENV = os.path.join(HERE, "..", ".env")
URL = "https://api.vworld.kr/ned/data/getApartHousingPriceAttr"


def env():
    d = {}
    for line in io.open(ENV, encoding="utf-8-sig"):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1); d[k.strip()] = v.strip().strip('"')
    return d


E = env(); KEY = (E.get("VWORLD_NED_KEY") or E.get("VWORLD_KEY") or "").strip(); DOM = (E.get("VWORLD_DOMAIN") or "localhost").strip()


def fetch(pnu):
    rows, page = [], 1
    while True:
        q = urllib.parse.urlencode({"key": KEY, "domain": DOM, "pnu": pnu, "format": "json", "numOfRows": "1000", "pageNo": str(page)})
        j = None; last = None
        for t in range(5):
            try:
                j = json.loads(urllib.request.urlopen(URL + "?" + q, timeout=60).read().decode("utf-8", "replace")); break
            except Exception as ex:
                last = str(ex).replace(KEY, "***")[:120]; time.sleep(1.5 * (t + 1))
        if j is None: raise RuntimeError(last or "?")
        a = j.get("apartHousingPrices")
        if not a:
            r = j.get("response") or {}
            if str(r.get("totalCount", "")) == "0": return rows
            raise RuntimeError("이상한 응답 " + json.dumps(j, ensure_ascii=False)[:100])
        f = a.get("field") or []
        if isinstance(f, dict): f = [f]
        rows += f
        tot = int(a.get("totalCount") or len(rows))
        if len(rows) >= tot or not f: return rows
        page += 1


def s(v):
    v = None if v is None else str(v).strip()
    return v or None


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--workers", type=int, default=4); ap.add_argument("--max-min", type=float, default=0)
    ap.add_argument("--target", default="rh", choices=["rh", "closed"],
                    help="rh = 연립·다세대 호가 있는 지금 필지(처음 것) · closed = 폐쇄·말소 집합 대장 지번(323 v_closed_detail_target, 2026-10-23 사장님 '2번 ㅇㅋ')")
    a = ap.parse_args()
    if not KEY: sys.exit(".env 에 VWORLD_NED_KEY / VWORLD_KEY 가 없습니다")
    import pymssql
    conn = pymssql.connect(server=E.get("DB_HOST", "127.0.0.1"), port=int(E.get("DB_PORT", 11433)), user=E.get("DB_USER", "sa"),
                           password=E.get("DB_PASSWORD", ""), database=E.get("DB_NAME", "Teomoony"), charset="UTF-8", autocommit=False)
    cur = conn.cursor()
    if a.target == "closed":
        cur.execute("""SELECT t.pnu FROM gold.v_closed_detail_target t
                        WHERE NOT EXISTS (SELECT 1 FROM silver.ned_aphus_done d WHERE d.pnu = t.pnu) ORDER BY t.차례, t.pnu""")
    else:
      cur.execute("""SELECT DISTINCT e.pnu FROM silver.bld_expos e
                    JOIN silver.bld_expos_pubuse_area x ON x.mgm_bldrgst_pk = e.mgm_bldrgst_pk AND x.is_current = 1
                     AND x.expos_pubuse_gb_cd = '1' AND x.main_purps_cd IN ('02002', '02003')
                   WHERE e.is_current = 1 AND e.pnu IS NOT NULL AND LEFT(e.pnu, 5) IN (SELECT sgg_cd FROM meta.v_target_sgg)   -- 2026-10-24: 적재 대상 시군구
                     AND NOT EXISTS (SELECT 1 FROM silver.ned_aphus_done d WHERE d.pnu = e.pnu)""")
    todo = [r[0] for r in cur.fetchall()]
    print(f"받을 필지 {len(todo):,}", flush=True)
    t0 = time.monotonic(); n = 0; 행 = 0; 실패 = 0
    # ★ 2026-10-23: 키 칸을 표의 형(CHAR · VARCHAR)으로 바꿔 넘긴다 — N'..'(nvarchar) 그대로면 PK 를 못 타고 표를 훑었다(한 줄 MERGE 에 읽기 20만 · 5분에 34줄).
    SQL = """MERGE silver.ned_aphus_price AS t USING (SELECT CAST(%s AS CHAR(19)) pnu, CAST(%s AS VARCHAR(20)) 공동주택코드, %s 동명, %s 호명, CAST(%s AS CHAR(4)) 기준연도, CAST(%s AS CHAR(2)) 기준월) k
             ON t.pnu = k.pnu AND t.공동주택코드 = k.공동주택코드 AND t.동명 = k.동명 AND t.호명 = k.호명 AND t.기준연도 = k.기준연도 AND t.기준월 = k.기준월
             WHEN MATCHED THEN UPDATE SET 층=%s, 전용면적=%s, 공시가격=%s, 공동주택명=%s, 구분=%s, 대장구분=%s, 특수지명=%s, 원문갱신일=%s, 받은시각=SYSDATETIME()
             WHEN NOT MATCHED THEN INSERT (pnu, 공동주택코드, 동명, 호명, 기준연도, 기준월, 층, 전용면적, 공시가격, 공동주택명, 구분, 대장구분, 특수지명, 원문갱신일)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s);"""
    with ThreadPoolExecutor(max_workers=a.workers) as ex:
        it = iter(todo); futs = {}
        def 채우기():
            for p in it:
                futs[ex.submit(fetch, p)] = p
                if len(futs) >= a.workers * 4: return
        채우기()
        while futs:
            f = next(as_completed(list(futs))); p = futs.pop(f)
            try:
                rows = f.result()
                for x in rows:
                    k = (p, s(x.get("aphusCode")) or "?", (x.get("dongNm") or "").strip(), (x.get("hoNm") or "").strip(),
                         s(x.get("stdrYear")) or "?", s(x.get("stdrMt")) or "01")
                    try: 가 = int(float(x.get("pblntfPc")))
                    except Exception: 가 = None
                    try: 면 = float(x.get("prvuseAr"))
                    except Exception: 면 = None
                    v = (s(x.get("floorNm")), 면, 가, s(x.get("aphusNm")), s(x.get("aphusSeCodeNm")), s(x.get("regstrSeCodeNm")),
                         s(x.get("spclLandNm")), s(x.get("lastUpdtDt")))
                    cur.execute(SQL, k + v + k + v)
                cur.execute("""MERGE silver.ned_aphus_done AS t USING (SELECT CAST(%s AS CHAR(19)) pnu) k ON t.pnu = k.pnu
                               WHEN MATCHED THEN UPDATE SET 건수 = %s, 받은시각 = SYSDATETIME()
                               WHEN NOT MATCHED THEN INSERT (pnu, 건수) VALUES (%s, %s);""", (p, len(rows), p, len(rows)))
                n += 1; 행 += len(rows)
            except Exception as e:
                실패 += 1
                if 실패 <= 20: print(f"  ! {p}: {str(e)[:120]}", flush=True)
            conn.commit()   # 2026-10-23: 필지마다 저장 — 100필지씩 묶으면 잠금이 표 전체로 커져 단지 상세가 1분씩 기다렸다(11-226)
            if n and n % 1000 == 0:
                print(f"  [{(time.monotonic() - t0) / 60:.1f}분] {n:,}/{len(todo):,} 필지 · 행 {행:,} · 실패 {실패}", flush=True)
            if a.max_min and (time.monotonic() - t0) / 60 > a.max_min:
                print(f"  ⏸ {a.max_min}분 — 멈춤(이어받기)", flush=True); break
            채우기()
    conn.commit(); conn.close()
    print(f"끝 {n:,}/{len(todo):,} 필지 · 행 {행:,} · 실패 {실패} · {(time.monotonic() - t0) / 60:.1f}분", flush=True)


if __name__ == "__main__":
    main()
