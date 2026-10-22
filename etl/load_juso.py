# -*- coding: utf-8 -*-
"""load_juso - 행정안전부 도로명주소 검색 API(addrLinkApi) → silver.juso_lookup / juso_result · meta.road_code  (2026-10-23, deploy/sql/320)

  py load_juso.py --what kapt               K-apt 도로명주소(서울·안양) — 이어받기
  py load_juso.py --what kapt --limit 20    시험

★ 키 = .env JUSO_KEY(운영키). 화면·로그에 안 찍는다.
★ 원문 그대로 — 응답 JSON 을 raw 에 통째로, 칸은 펼쳐 둔다. 0건도 '물어봤음'. 오류(키·한도)는 적지 않고 멈춘다 — 다음에 다시.
★ 사장님 "법정동 도로명 모두 마스터와 같은 방식" — 받은 도로명코드는 meta.road_code 에 넣는다(meta.usp_road_code_from_juso).
"""
import argparse, io, json, os, sys, time, urllib.parse, urllib.request
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
ENV = os.path.join(HERE, "..", ".env")
URL = "https://business.juso.go.kr/addrlink/addrLinkApi.do"


def env():
    d = {}
    for line in io.open(ENV, encoding="utf-8-sig"):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1); d[k.strip()] = v.strip().strip('"')
    return d


E = env(); KEY = E.get("JUSO_KEY", "").strip()
ASK = {"kapt": "SELECT keyword FROM gold.v_juso_ask_kapt v WHERE NOT EXISTS (SELECT 1 FROM silver.juso_lookup l WHERE l.keyword = v.keyword)"}
STOP = {"E0001", "E0014", "E0015", "-999"}      # 키 오류 · 한도 · 시스템 — 멈춘다


def connect():
    import pymssql
    return pymssql.connect(server=E.get("DB_HOST", "127.0.0.1"), port=int(E.get("DB_PORT", 11433)), user=E.get("DB_USER", "sa"),
                           password=E.get("DB_PASSWORD", ""), database=E.get("DB_NAME", "Teomoony"), charset="UTF-8", autocommit=False)


def fetch(kw):
    q = urllib.parse.urlencode({"confmKey": KEY, "currentPage": "1", "countPerPage": "20", "keyword": kw, "resultType": "json"})
    last = None
    for t in range(4):
        try:
            raw = urllib.request.urlopen(URL + "?" + q, timeout=30).read().decode("utf-8", "replace")
            return raw, json.loads(raw)
        except Exception as ex:
            last = str(ex).replace(KEY, "***")[:120]; time.sleep(1.5 * (t + 1))
    raise RuntimeError(last or "?")


def i(v):
    try: return int(str(v).strip())
    except Exception: return None


def s(v):
    v = None if v is None else str(v).strip()
    return v or None


def write(cur, kw, 출처, raw, j):
    c = (j.get("results") or {}).get("common") or {}
    code, msg = s(c.get("errorCode")), s(c.get("errorMessage"))
    rows = (j.get("results") or {}).get("juso") or []
    cur.execute("DELETE FROM silver.juso_result WHERE keyword = %s", (kw,))
    cur.execute("""MERGE silver.juso_lookup AS t USING (SELECT %s AS keyword) k ON t.keyword = k.keyword
                   WHEN MATCHED THEN UPDATE SET 출처=%s, total_count=%s, error_code=%s, error_message=%s, raw=%s, 받은때=SYSDATETIME()
                   WHEN NOT MATCHED THEN INSERT (keyword, 출처, total_count, error_code, error_message, raw) VALUES (%s, %s, %s, %s, %s, %s);""",
                (kw, 출처, i(c.get("totalCount")), code, msg, raw, kw, 출처, i(c.get("totalCount")), code, msg, raw))
    for n, x in enumerate(rows, 1):
        cur.execute("""INSERT INTO silver.juso_result (keyword, 순, road_addr, jibun_addr, adm_cd, rn_mgt_sn, rn, udrt_yn, buld_mnnm, buld_slno,
                                                      mt_yn, lnbr_mnnm, lnbr_slno, bd_mgt_sn, bd_nm, bd_kdcd)
                       VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
                    (kw, n, s(x.get("roadAddr")), s(x.get("jibunAddr")), s(x.get("admCd")), s(x.get("rnMgtSn")), s(x.get("rn")),
                     s(x.get("udrtYn")), i(x.get("buldMnnm")), i(x.get("buldSlno")), s(x.get("mtYn")), i(x.get("lnbrMnnm")),
                     i(x.get("lnbrSlno")), s(x.get("bdMgtSn")), s(x.get("bdNm")), s(x.get("bdKdcd"))))
    return code, len(rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--what", default="kapt", choices=sorted(ASK)); ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--workers", type=int, default=3)
    a = ap.parse_args()
    if not KEY: sys.exit(".env 의 JUSO_KEY 가 비어 있습니다")
    conn = connect(); cur = conn.cursor()
    cur.execute(ASK[a.what]); todo = [r[0] for r in cur.fetchall() if r[0]]
    if a.limit: todo = todo[:a.limit]
    print(f"[{a.what}] 물을 주소 {len(todo):,}", flush=True)
    t0 = time.monotonic(); n = 0; 결과 = {"0건": 0, "1건": 0, "여럿": 0}; 실패 = 0; 멈춤 = None
    with ThreadPoolExecutor(max_workers=a.workers) as ex:
        for k0 in range(0, len(todo), 30):
            묶음 = todo[k0:k0 + 30]
            for kw, r in zip(묶음, ex.map(lambda k: _try(k), 묶음)):
                if isinstance(r, Exception):
                    실패 += 1
                    if 실패 <= 10: print(f"  ! {kw}: {str(r)[:100]}", flush=True)
                    continue
                raw, j = r
                code = s(((j.get("results") or {}).get("common") or {}).get("errorCode"))
                if code in STOP:
                    멈춤 = f"{code} {s(((j.get('results') or {}).get('common') or {}).get('errorMessage'))}"; break
                code, m = write(cur, kw, a.what.upper(), raw, j); n += 1
                결과["0건" if m == 0 else "1건" if m == 1 else "여럿"] += 1
            conn.commit()
            if 멈춤: break
            if n and n % 300 < 30:
                print(f"  [{(time.monotonic() - t0) / 60:.1f}분] {n:,}/{len(todo):,} · {결과} · 실패 {실패}", flush=True)
    cur.execute("EXEC meta.usp_road_code_from_juso"); 도로 = cur.fetchone(); conn.commit()
    print(f"[{a.what}] 끝 {n:,}/{len(todo):,} · {결과} · 실패 {실패} · 도로명 마스터 {도로[0] if 도로 else '?'}개"
          + (f" · ⏸ 멈춤: {멈춤}" if 멈춤 else ""), flush=True)


def _try(k):
    try: return fetch(k)
    except Exception as e: return e


if __name__ == "__main__":
    main()
