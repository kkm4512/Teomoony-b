# -*- coding: utf-8 -*-
"""load_closed_detail - 폐쇄·말소 대장 전유부 · 전유공용면적 · 층별개요 → silver.bld_closed_*  (2026-10-23, deploy/sql/323)

  py load_closed_detail.py                     차례 1(옛 건물 실거래가 있는 집합 지번) → 차례 2(나머지) · 이어받기
  py load_closed_detail.py --only 1 --limit 5  시험

출처: 공공데이터포털 15137093 ShtRgstHubService. 키 = .env DATA_GO_KR_KEY — 화면·로그에 안 찍는다.
★ 지번 하나 · 항목 하나씩. 받은 줄 = totalCount 일 때만 넣는다(지우고 다시). 한도·키 오류면 멈춘다 — 다음에 이어받기.
★ 원문 0/빈칸 = NULL. 주택가격은 안 받는다(기준일이 없다 — 323 머리말).
"""
import argparse, io, json, os, re, sys, threading, time, urllib.error, urllib.parse, urllib.request
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
ENV = os.path.join(HERE, "..", ".env")
BASE = "https://apis.data.go.kr/1613000/ShtRgstHubService/"


def env():
    d = {}
    for line in io.open(ENV, encoding="utf-8-sig"):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1); d[k.strip()] = v.strip().strip('"')
    return d


E = env(); KEY = E.get("DATA_GO_KR_KEY", "").strip()


class Stop(Exception):
    pass


def s(v):
    v = None if v is None else str(v).strip()
    return v or None


def i(v):
    try: return int(str(v).strip())
    except Exception: return None


def f(v):
    try:
        x = float(str(v).replace(",", ""))
        return None if x == 0 else x
    except Exception: return None


def d8(v):
    v = s(v); return v if v and re.fullmatch(r"\d{8}", v) else None


GAP = 0.12                     # 호출 사이 최소 간격(초) — 첫 판(4줄 · 간격 없음)에 HTTP 429 Too Many Requests 가 났다
_LOCK = threading.Lock(); _LAST = [0.0]


def 차례지키기():
    with _LOCK:
        w = _LAST[0] + GAP - time.monotonic()
        if w > 0: time.sleep(w)
        _LAST[0] = time.monotonic()


def call(op, t, page):
    q = urllib.parse.urlencode({"sigunguCd": t[1], "bjdongCd": t[2], "platGbCd": t[3] or "0", "bun": t[4], "ji": t[5],
                                "numOfRows": 100, "pageNo": page, "_type": "json"})
    u = BASE + op + "?serviceKey=" + KEY + "&" + q; last = None
    for k in range(6):
        try:
            차례지키기()
            raw = urllib.request.urlopen(u, timeout=60).read().decode("utf-8", "replace")
            try: j = json.loads(raw)
            except Exception:
                if "LIMITED" in raw or "SERVICE_KEY" in raw or "SERVICE ERROR" in raw: raise Stop(raw[:160].replace(KEY, "***"))
                raise RuntimeError("JSON 아님 " + raw[:120].replace(KEY, "***"))
            h = (j.get("response") or {}).get("header") or {}
            code = h.get("resultCode")
            if code in ("22", "30", "31", "32", "20", "33"): raise Stop(f"resultCode={code} {h.get('resultMsg')}")
            if code != "00": raise RuntimeError(f"resultCode={code} {h.get('resultMsg')}")
            b = (j.get("response") or {}).get("body") or {}
            it = b.get("items") or {}
            it = it.get("item", []) if isinstance(it, dict) else []
            return int(b.get("totalCount") or 0), ([it] if isinstance(it, dict) else it)
        except Stop: raise
        except urllib.error.HTTPError as ex:
            last = f"HTTP {ex.code}"
            time.sleep(15 * (k + 1) if ex.code == 429 else 2 * (k + 1))     # 429 = 너무 잦다 — 길게 쉰다
        except Exception as ex:
            last = str(ex).replace(KEY, "***")[:160]; time.sleep(2 * (k + 1))
    raise RuntimeError(last or "?")


def all_rows(op, t):
    tot, rows = call(op, t, 1); p = 1
    while len(rows) < tot:
        p += 1; _, more = call(op, t, p)
        if not more: break
        rows += more
    if len(rows) != tot: raise RuntimeError(f"받은 {len(rows)} ≠ totalCount {tot}")
    return rows


OPS = {
    "getSrExposInfo": ("silver.bld_closed_expos",
        ["mgm_shtreg_pk", "pnu", "shter_gb_nm", "regstr_kind_nm", "bld_nm", "dong_nm", "ho_nm", "flr_gb_nm", "flr_no", "crtn_day"],
        lambda x, p: (s(x.get("mgmShtregPk")), p, s(x.get("shterGbCdNm")), s(x.get("regstrKindCdNm")), s(x.get("bldNm")), s(x.get("dongNm")),
                      s(x.get("hoNm")), s(x.get("flrGbCdNm")), i(x.get("flrNo")), d8(x.get("crtnDay")))),
    "getSrExposPubuseAreaInfo": ("silver.bld_closed_expos_area",
        ["mgm_shtreg_pk", "pnu", "dong_nm", "ho_nm", "flr_gb_nm", "flr_no", "flr_no_nm", "expos_pubuse_gb_nm", "main_atch_gb_nm",
         "main_purps_nm", "etc_purps", "strct_nm", "area", "crtn_day"],
        lambda x, p: (s(x.get("mgmShtregPk")), p, s(x.get("dongNm")), s(x.get("hoNm")), s(x.get("flrGbCdNm")), i(x.get("flrNo")), s(x.get("flrNoNm")),
                      s(x.get("exposPubuseGbCdNm")), s(x.get("mainAtchGbCdNm")), s(x.get("mainPurpsCdNm")), s(x.get("etcPurps")),
                      s(x.get("strctCdNm")), f(x.get("area")), d8(x.get("crtnDay")))),
    "getSrFlrOulnInfo": ("silver.bld_closed_flr",
        ["mgm_shtreg_pk", "pnu", "dong_nm", "flr_gb_nm", "flr_no", "flr_no_nm", "main_atch_gb_nm", "main_purps_nm", "etc_purps", "strct_nm", "area", "crtn_day"],
        lambda x, p: (s(x.get("mgmShtregPk")), p, s(x.get("dongNm")), s(x.get("flrGbCdNm")), i(x.get("flrNo")), s(x.get("flrNoNm")),
                      s(x.get("mainAtchGbCdNm")), s(x.get("mainPurpsCdNm")), s(x.get("etcPurps")), s(x.get("strctCdNm")), f(x.get("area")), d8(x.get("crtnDay")))),
}


def connect():
    import pymssql
    return pymssql.connect(server=E.get("DB_HOST", "127.0.0.1"), port=int(E.get("DB_PORT", 11433)), user=E.get("DB_USER", "sa"),
                           password=E.get("DB_PASSWORD", ""), database=E.get("DB_NAME", "Teomoony"), charset="UTF-8", autocommit=False)


def write(cur, op, pnu, rows):
    table, cols, fn = OPS[op]
    cur.execute(f"DELETE FROM {table} WHERE pnu = %s", (pnu,))
    vals = [fn(x, pnu) for x in rows]
    if op == "getSrExposInfo":                     # pk 가 겹치면(같은 호가 두 번) 하나만
        seen = set(); vals = [v for v in vals if v[0] and not (v[0] in seen or seen.add(v[0]))]
    if vals:
        cur.executemany(f"INSERT INTO {table} ({', '.join(cols)}) VALUES ({', '.join(['%s'] * len(cols))})", vals)
    cur.execute("""MERGE silver.bld_closed_detail_done AS t USING (SELECT %s AS pnu, %s AS op) k ON t.pnu = k.pnu AND t.op = k.op
                   WHEN MATCHED THEN UPDATE SET 건수 = %s, 받은때 = SYSDATETIME()
                   WHEN NOT MATCHED THEN INSERT (pnu, op, 건수) VALUES (%s, %s, %s);""", (pnu, op, len(rows), pnu, op, len(rows)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", type=int, default=[1, 2]); ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--workers", type=int, default=2); ap.add_argument("--ops", nargs="*", default=list(OPS))
    a = ap.parse_args()
    if not KEY: sys.exit(".env 의 DATA_GO_KR_KEY 가 비어 있습니다")
    conn = connect(); cur = conn.cursor()
    t0 = time.monotonic(); 호출 = 0; 멈춤 = None
    for 차례 in a.only:
        for op in a.ops:
            cur.execute("""SELECT t.pnu, t.sigungu_cd, t.bjdong_cd, t.plat_gb_cd, t.bun, t.ji FROM gold.v_closed_detail_target t
                            WHERE t.차례 = %s AND NOT EXISTS (SELECT 1 FROM silver.bld_closed_detail_done d WHERE d.pnu = t.pnu AND d.op = %s)
                            ORDER BY t.pnu""", (차례, op))
            todo = cur.fetchall()
            if a.limit: todo = todo[:a.limit]
            print(f"[차례 {차례} · {op}] 지번 {len(todo):,}", flush=True)
            n = 줄 = 실패 = 0

            def job(t):
                try: return t, all_rows(op, t), None
                except Stop as e: return t, None, ("STOP", str(e))
                except Exception as e: return t, None, ("ERR", str(e))
            with ThreadPoolExecutor(max_workers=a.workers) as ex:
                for k0 in range(0, len(todo), 40):
                    for t, rows, err in ex.map(job, todo[k0:k0 + 40]):
                        if err:
                            if err[0] == "STOP": 멈춤 = err[1]; continue
                            실패 += 1
                            if 실패 <= 10: print(f"  ! {t[0]}: {err[1][:120]}", flush=True)
                            continue
                        write(cur, op, t[0], rows); n += 1; 줄 += len(rows); 호출 += max(1, -(-len(rows) // 100))
                    conn.commit()
                    if 멈춤: break
                    if n and n % 400 < 40:
                        print(f"  [{(time.monotonic() - t0) / 60:.1f}분] {n:,}/{len(todo):,} 지번 · {줄:,}줄 · 실패 {실패} · 호출 약 {호출:,}", flush=True)
            print(f"[차례 {차례} · {op}] 끝 {n:,}/{len(todo):,} 지번 · {줄:,}줄 · 실패 {실패}", flush=True)
            if 멈춤: break
        if 멈춤: break
    print(f"합 호출 약 {호출:,} · {(time.monotonic() - t0) / 60:.1f}분" + (f" · ⏸ 멈춤(한도·키): {멈춤}" if 멈춤 else ""), flush=True)


if __name__ == "__main__":
    main()
