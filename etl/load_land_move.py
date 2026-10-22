# -*- coding: utf-8 -*-
"""load_land_move - VWorld 토지이동이력(getLandMoveAttr) → silver.land_move_hist  (2026-10-22, deploy/sql/305)

  py load_land_move.py                    ①공고 지번(지도에 없음) ②폐쇄 대장 필지(지도에 없음) ③서울·안양 지금 필지 전부 — 이어받기
  py load_land_move.py --only 1 2         차례 골라서
  py load_land_move.py --workers 4 --max-min 600

★ 키 = .env VWORLD_KEY(도메인 VWORLD_DOMAIN). 화면·로그에 안 찍는다.
★ 원문 그대로. 이력 0건도 '다 받음'(done). 실패한 필지는 done 에 안 적는다 — 다음에 다시.
★ DB 는 한 연결(주 스레드)에서만 쓴다. 받기만 여러 스레드.
"""
import argparse, io, json, os, sys, time, urllib.parse, urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

HERE = os.path.dirname(os.path.abspath(__file__))
ENV = os.path.join(HERE, "..", ".env")
URL = "https://api.vworld.kr/ned/data/getLandMoveAttr"


def env():
    d = {}
    for line in io.open(ENV, encoding="utf-8-sig"):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1); d[k.strip()] = v.strip().strip('"')
    return d


E = env(); KEY = E.get("VWORLD_KEY", "").strip(); DOM = (E.get("VWORLD_DOMAIN") or "localhost").strip()


def fetch(pnu):
    rows, page = [], 1
    while True:
        q = urllib.parse.urlencode({"key": KEY, "domain": DOM, "pnu": pnu, "format": "json", "numOfRows": "100", "pageNo": str(page)})
        last = None
        for t in range(5):
            try:
                raw = urllib.request.urlopen(URL + "?" + q, timeout=40).read().decode("utf-8", "replace")
                j = json.loads(raw)
                break
            except Exception as ex:
                last = str(ex).replace(KEY, "***")[:120]; j = None; time.sleep(1.5 * (t + 1))
        if j is None: raise RuntimeError(last or "?")
        lm = j.get("landMoves")
        if not lm:
            r = j.get("response") or {}
            if str(r.get("totalCount", "")) == "0": return rows       # 이력 없음
            raise RuntimeError("이상한 응답 " + json.dumps(j, ensure_ascii=False)[:100])
        f = lm.get("field") or []
        if isinstance(f, dict): f = [f]
        rows += f
        tot = int(lm.get("totalCount") or len(rows))
        if len(rows) >= tot or not f: return rows
        page += 1


def s(v):
    v = None if v is None else str(v).strip()
    return v or None


def num(v):
    try: return float(str(v).replace(",", ""))
    except Exception: return None


def connect():
    import pymssql
    return pymssql.connect(server=E.get("DB_HOST", "127.0.0.1"), port=int(E.get("DB_PORT", 11433)), user=E.get("DB_USER", "sa"),
                           password=E.get("DB_PASSWORD", ""), database=E.get("DB_NAME", "Teomoony"), charset="UTF-8", autocommit=False)


TARGET = {
    1: """SELECT DISTINCT p.pnu FROM silver.applyhome_pblanc p
           WHERE p.pnu IS NOT NULL AND NOT EXISTS (SELECT 1 FROM silver.cadastral_parcel c WHERE c.pnu = p.pnu AND c.is_current = 1)""",
    2: """SELECT DISTINCT s.pnu FROM gold.closed_site s
           WHERE NOT EXISTS (SELECT 1 FROM silver.cadastral_parcel c WHERE c.pnu = s.pnu AND c.is_current = 1)""",
    3: """SELECT c.pnu FROM silver.cadastral_parcel c
           WHERE c.is_current = 1 AND (LEFT(c.pnu, 2) = '11' OR LEFT(c.pnu, 5) IN ('41171', '41173'))""",
}
MERGE = """MERGE silver.land_move_hist AS t
USING (SELECT %s AS pnu, %s AS 대장코드, %s AS 이력순번) AS k ON t.pnu = k.pnu AND t.대장코드 = k.대장코드 AND t.이력순번 = k.이력순번
WHEN MATCHED THEN UPDATE SET 이력일련=%s, 대장=%s, 이동일=%s, 이동사유코드=%s, 이동사유=%s, 소멸일=%s, 지번=%s, 지목코드=%s, 지목=%s, 면적=%s, 원문갱신일=%s, 받은시각=SYSDATETIME()
WHEN NOT MATCHED THEN INSERT (pnu, 대장코드, 이력순번, 이력일련, 대장, 이동일, 이동사유코드, 이동사유, 소멸일, 지번, 지목코드, 지목, 면적, 원문갱신일)
  VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s);"""


def write(cur, pnu, rows, 차례):
    for x in rows:
        k = (pnu, s(x.get("regstrSeCode")) or "?", s(x.get("ladHistSn")) or "?")
        v = (s(x.get("ladMvmnHistSn")), s(x.get("regstrSeCodeNm")), s(x.get("ladMvmnDe")), s(x.get("ladMvmnPrvonshCode")),
             s(x.get("ladMvmnPrvonshCodeNm")), s(x.get("ladMvmnErsrDe")), s(x.get("mnnmSlno")), s(x.get("lndcgrCode")),
             s(x.get("lndcgrCodeNm")), num(x.get("lndpclAr")), s(x.get("lastUpdtDt")))
        cur.execute(MERGE, k + v + k + v)
    cur.execute("""MERGE silver.land_move_done AS t USING (SELECT %s AS pnu) k ON t.pnu = k.pnu
                   WHEN MATCHED THEN UPDATE SET 건수 = %s, 차례 = %s, 받은시각 = SYSDATETIME()
                   WHEN NOT MATCHED THEN INSERT (pnu, 건수, 차례) VALUES (%s, %s, %s);""", (pnu, len(rows), 차례, pnu, len(rows), 차례))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", type=int, default=[1, 2, 3]); ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--max-min", type=float, default=0)
    a = ap.parse_args()
    if not KEY: sys.exit(".env 의 VWORLD_KEY 가 비어 있습니다")
    conn = connect(); cur = conn.cursor()
    cur.execute("SELECT pnu FROM silver.land_move_done"); done = {r[0] for r in cur.fetchall()}
    t0 = time.monotonic(); 합 = 0; 실패 = []
    for 차례 in a.only:
        cur.execute(TARGET[차례]); todo = [r[0] for r in cur.fetchall() if r[0] and r[0] not in done]
        print(f"[차례 {차례}] 받을 필지 {len(todo):,} (이미 받은 {len(done):,} 제외)", flush=True)
        n = 0; 이력 = 0
        with ThreadPoolExecutor(max_workers=a.workers) as ex:
            futs = {}
            it = iter(todo)
            def 채우기():
                for p in it:
                    futs[ex.submit(fetch, p)] = p
                    if len(futs) >= a.workers * 4: return
            채우기()
            while futs:
                for f in as_completed(list(futs)):
                    p = futs.pop(f)
                    try:
                        rows = f.result(); write(cur, p, rows, 차례); done.add(p); n += 1; 이력 += len(rows)
                    except Exception as e:
                        실패.append(p)
                        if len(실패) <= 20: print(f"  ! {p}: {str(e)[:120]}", flush=True)
                    if n % 200 == 0: conn.commit()
                    if n and n % 2000 == 0:
                        m = (time.monotonic() - t0) / 60
                        print(f"  [{m:.1f}분] 차례 {차례}: {n:,}/{len(todo):,} 필지 · 이력 {이력:,} · 실패 {len(실패)}", flush=True)
                    break
                채우기()
                if a.max_min and (time.monotonic() - t0) / 60 > a.max_min:
                    print(f"  ⏸ {a.max_min}분 넘어 멈춤 — 다음에 이어받기", flush=True); futs.clear(); break
        conn.commit(); 합 += n
        print(f"[차례 {차례}] 끝 {n:,}/{len(todo):,} 필지 · 이력 {이력:,}", flush=True)
        if a.max_min and (time.monotonic() - t0) / 60 > a.max_min: break
    print(f"합 {합:,} 필지 · 실패 {len(실패):,} (다시 돌리면 실패분만 이어받음) · {(time.monotonic() - t0) / 60:.1f}분", flush=True)
    conn.close()


if __name__ == "__main__":
    main()
