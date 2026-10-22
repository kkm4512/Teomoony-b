# -*- coding: utf-8 -*-
"""load_closed_bld - 폐쇄말소 건축물대장(표제부·총괄표제부) 적재  2026-10-22  (deploy/sql/302)

  py load_closed_bld.py --lawd 1129013800 1138010100          법정동 몇 개
  py load_closed_bld.py --sgg 11290 11380                       시군구 통째(meta.lawd_code 의 법정동 전부)
  py load_closed_bld.py --lawd ... --sql-out 파일               DB 대신 SQL 파일(작업 줄이 막혔을 때 /api/_apply 로)

출처: 공공데이터포털 15137093 ShtRgstHubService (getSrTitleInfo · getSrRecapTitleInfo). 키 = .env DATA_GO_KR_KEY — 화면·로그에 안 찍는다.
★ 원문 0 · 빈칸(' ') = '안 적음' → NULL. 날짜는 8자리 숫자만, 아니면 NULL. 말소일·사유를 지어내지 않는다.
★ 다 받은 뒤에만 넣는다(쪽 수 = totalCount 확인). 덜 받았으면 그 법정동은 넣지 않고 멈춘다.
"""
import argparse, io, json, os, re, sys, time, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ENV = os.path.join(HERE, "..", ".env")
BASE = "https://apis.data.go.kr/1613000/ShtRgstHubService/"


def env():
    d = {}
    try:
        for line in io.open(ENV, encoding="utf-8-sig"):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1); d[k.strip()] = v.strip().strip('"')
    except FileNotFoundError:
        pass
    return d


def call(key, op, sgg, bjd, page):
    q = urllib.parse.urlencode({"sigunguCd": sgg, "bjdongCd": bjd, "numOfRows": 100, "pageNo": page, "_type": "json"})
    u = BASE + op + "?serviceKey=" + key + "&" + q
    for t in range(4):
        try:
            with urllib.request.urlopen(u, timeout=60) as r:
                j = json.loads(r.read().decode("utf-8", "replace"))
            rsp = j.get("response") or {}
            code = (rsp.get("header") or {}).get("resultCode")
            if code != "00":
                raise RuntimeError(f"resultCode={code} {json.dumps(j, ensure_ascii=False)[:160]}")
            b = rsp.get("body") or {}
            it = b.get("items") or {}
            it = it.get("item", []) if isinstance(it, dict) else []
            return int(b.get("totalCount") or 0), ([it] if isinstance(it, dict) else it)
        except Exception as ex:
            if t == 3: raise RuntimeError(f"{op} {sgg}{bjd} p{page}: {str(ex).replace(key, '***')[:200]}")
            time.sleep(2 * (t + 1))


def all_rows(key, op, sgg, bjd):
    tot, rows = call(key, op, sgg, bjd, 1); p = 1
    while len(rows) < tot:
        p += 1; _, more = call(key, op, sgg, bjd, p)
        if not more: break
        rows += more; time.sleep(0.05)
    if len(rows) != tot: raise RuntimeError(f"{op} {sgg}{bjd}: 받은 {len(rows)} ≠ totalCount {tot}")
    return rows


def s(v):
    v = None if v is None else str(v).strip()
    return v or None


def n(v, as_int=False):
    try:
        f = float(str(v).replace(",", ""))
    except Exception:
        return None
    if f == 0: return None                    # 원문 0 = 안 적음
    return int(round(f)) if as_int else f


def d8(v):
    v = s(v)
    return v if v and re.fullmatch(r"\d{8}", v) else None


TCOLS = [("mgm_shtreg_pk", lambda x: s(x.get("mgmShtregPk"))), ("shter_gb_cd", lambda x: s(x.get("shterGbCd"))),
         ("shter_gb_nm", lambda x: s(x.get("shterGbCdNm"))), ("shter_day", lambda x: d8(x.get("shterDay"))),
         ("regstr_gb_nm", lambda x: s(x.get("regstrGbCdNm"))), ("regstr_kind_nm", lambda x: s(x.get("regstrKindCdNm"))),
         ("sigungu_cd", lambda x: s(x.get("sigunguCd"))), ("bjdong_cd", lambda x: s(x.get("bjdongCd"))),
         ("plat_gb_cd", lambda x: s(x.get("platGbCd"))), ("bun", lambda x: s(x.get("bun"))), ("ji", lambda x: s(x.get("ji"))),
         ("plat_plc", lambda x: s(x.get("platPlc"))), ("new_plat_plc", lambda x: s(x.get("newPlatPlc"))),
         ("bld_nm", lambda x: s(x.get("bldNm"))), ("dong_nm", lambda x: s(x.get("dongNm"))),
         ("main_atch_gb_nm", lambda x: s(x.get("mainAtchGbCdNm"))),
         ("plat_area", lambda x: n(x.get("platArea"))), ("arch_area", lambda x: n(x.get("archArea"))), ("bc_rat", lambda x: n(x.get("bcRat"))),
         ("tot_area", lambda x: n(x.get("totArea"))), ("vl_rat", lambda x: n(x.get("vlRat"))), ("strct_nm", lambda x: s(x.get("strctCdNm"))),
         ("main_purps_cd", lambda x: s(x.get("mainPurpsCd"))), ("main_purps_nm", lambda x: s(x.get("mainPurpsCdNm"))),
         ("etc_purps", lambda x: s(x.get("etcPurps"))), ("hhld_cnt", lambda x: n(x.get("hhldCnt"), 1)), ("fmly_cnt", lambda x: n(x.get("fmlyCnt"), 1)),
         ("ho_cnt", lambda x: n(x.get("hoCnt"), 1)), ("heit", lambda x: n(x.get("heit"))), ("grnd_flr_cnt", lambda x: n(x.get("grndFlrCnt"), 1)),
         ("ugrnd_flr_cnt", lambda x: n(x.get("ugrndFlrCnt"), 1)), ("use_apr_day", lambda x: d8(x.get("useAprDay"))),
         ("pms_day", lambda x: d8(x.get("pmsDay"))), ("stcns_day", lambda x: d8(x.get("stcnsDay"))), ("crtn_day", lambda x: d8(x.get("crtnDay")))]
RCOLS = [("mgm_shtreg_pk", lambda x: s(x.get("mgmShtregPk"))), ("shter_gb_cd", lambda x: s(x.get("shterGbCd"))),
         ("shter_gb_nm", lambda x: s(x.get("shterGbCdNm"))), ("shter_day", lambda x: d8(x.get("shterDay"))),
         ("regstr_gb_nm", lambda x: s(x.get("regstrGbCdNm"))), ("new_old_regstr_gb_nm", lambda x: s(x.get("newOldRegstrGbCdNm"))),
         ("sigungu_cd", lambda x: s(x.get("sigunguCd"))), ("bjdong_cd", lambda x: s(x.get("bjdongCd"))),
         ("plat_gb_cd", lambda x: s(x.get("platGbCd"))), ("bun", lambda x: s(x.get("bun"))), ("ji", lambda x: s(x.get("ji"))),
         ("plat_plc", lambda x: s(x.get("platPlc"))), ("new_plat_plc", lambda x: s(x.get("newPlatPlc"))), ("bld_nm", lambda x: s(x.get("bldNm"))),
         ("plat_area", lambda x: n(x.get("platArea"))), ("arch_area", lambda x: n(x.get("archArea"))), ("bc_rat", lambda x: n(x.get("bcRat"))),
         ("tot_area", lambda x: n(x.get("totArea"))), ("vl_rat", lambda x: n(x.get("vlRat"))), ("main_purps_nm", lambda x: s(x.get("mainPurpsCdNm"))),
         ("main_bld_cnt", lambda x: n(x.get("mainBldCnt"), 1)), ("atch_bld_cnt", lambda x: n(x.get("atchBldCnt"), 1)),
         ("hhld_cnt", lambda x: n(x.get("hhldCnt"), 1)), ("fmly_cnt", lambda x: n(x.get("fmlyCnt"), 1)), ("ho_cnt", lambda x: n(x.get("hoCnt"), 1)),
         ("tot_pkng_cnt", lambda x: n(x.get("totPkngCnt"), 1)), ("use_apr_day", lambda x: d8(x.get("useAprDay"))),
         ("pms_day", lambda x: d8(x.get("pmsDay"))), ("crtn_day", lambda x: d8(x.get("crtnDay")))]
OPS = [("getSrTitleInfo", "silver.bld_closed_title", TCOLS), ("getSrRecapTitleInfo", "silver.bld_closed_recap", RCOLS)]


def q(v):
    if v is None: return "NULL"
    if isinstance(v, (int, float)): return repr(v)
    return "N'" + str(v).replace("'", "''") + "'"


def merge_sql(table, cols, rows):
    names = [c for c, _ in cols]; out = []
    for i in range(0, len(rows), 200):
        vals = ",\n".join("(" + ",".join(q(r[c]) for c in names) + ")" for r in rows[i:i + 200])
        out.append(f"MERGE {table} AS t USING (VALUES\n{vals}\n) AS s({', '.join(names)}) ON t.mgm_shtreg_pk = s.mgm_shtreg_pk\n"
                   f"WHEN MATCHED THEN UPDATE SET {', '.join(f't.{c}=s.{c}' for c in names[1:])}, "
                   f"t.pnu=meta.fn_make_pnu(s.sigungu_cd, s.bjdong_cd, s.plat_gb_cd, s.bun, s.ji), t.loaded_at=SYSDATETIME()\n"
                   f"WHEN NOT MATCHED THEN INSERT ({', '.join(names)}, pnu) VALUES ({', '.join('s.' + c for c in names)}, "
                   f"meta.fn_make_pnu(s.sigungu_cd, s.bjdong_cd, s.plat_gb_cd, s.bun, s.ji));\nGO\n")
    return out


def lawds_of(conn, sggs):
    cur = conn.cursor()
    cur.execute("SELECT lawd_cd FROM meta.lawd_code WHERE is_abolished = 0 AND RIGHT(lawd_cd,5) <> '00000' AND LEFT(lawd_cd,5) IN (" +
                ",".join(["%s"] * len(sggs)) + ") ORDER BY lawd_cd", tuple(sggs))
    return [r[0].strip() for r in cur.fetchall()]


def connect():
    import pymssql
    e = env()
    return pymssql.connect(server=e.get("DB_HOST", "127.0.0.1"), port=int(e.get("DB_PORT", 11433)), user=e.get("DB_USER", "sa"),
                           password=e.get("DB_PASSWORD", ""), database=e.get("DB_NAME", "Teomoony"), charset="UTF-8", autocommit=False)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lawd", nargs="*", default=[]); ap.add_argument("--sgg", nargs="*", default=[]); ap.add_argument("--sql-out")
    ap.add_argument("--skip-loaded", action="store_true", help="이미 폐쇄 표제부가 들어간 법정동은 건너뛴다(이어받기)")
    a = ap.parse_args()
    key = os.environ.get("DATA_GO_KR_KEY") or env().get("DATA_GO_KR_KEY", "")
    if not key: sys.exit(".env 의 DATA_GO_KR_KEY 가 비어 있습니다")
    conn = None if a.sql_out else connect()
    lawds = list(a.lawd) + (lawds_of(conn, a.sgg) if a.sgg and conn else [])
    if a.sgg and not conn: sys.exit("--sgg 는 DB 에서 법정동 목록을 읽습니다 — --sql-out 일 땐 --lawd 로 주세요")
    if not lawds: sys.exit("--lawd 나 --sgg 를 주세요")
    if a.skip_loaded and conn:
        cur = conn.cursor()
        cur.execute("SELECT DISTINCT LEFT(pnu,10) FROM silver.bld_closed_title WHERE pnu IS NOT NULL")
        있음 = {r[0] for r in cur.fetchall()}
        n0 = len(lawds); lawds = [x for x in lawds if x not in 있음]
        print(f"  이미 받은 법정동 {n0 - len(lawds)}곳 건너뜀", flush=True)
    sql = ["/* load_closed_bld.py --sql-out (302) */\nSET NOCOUNT ON;\nGO\n"]; 합 = {}; 실패 = []
    t0 = time.monotonic()
    for i, lw in enumerate(lawds, 1):
        sgg, bjd = lw[:5], lw[5:10]
        got = {}
        try:
            for op, table, cols in OPS:
                raw = all_rows(key, op, sgg, bjd)
                rows = [{c: f(x) for c, f in cols} for x in raw]
                rows = [r for r in rows if r["mgm_shtreg_pk"]]
                got[op] = (table, cols, rows)
        except Exception as ex:
            # ★ 덜 받은 법정동은 **넣지 않는다**(totalCount 확인). 나머지는 계속 받는다 — 끝에 목록으로 말한다.
            실패.append((lw, str(ex)[:120])); print(f"  [{i}/{len(lawds)}] {lw} ★ 실패 — 넣지 않음: {str(ex)[:120]}", flush=True); continue
        for op, (table, cols, rows) in got.items(): 합[op] = 합.get(op, 0) + len(rows)
        print(f"  [{i}/{len(lawds)}] {lw} 표제부 {len(got['getSrTitleInfo'][2]):,} · 총괄 {len(got['getSrRecapTitleInfo'][2]):,}"
              f"  ({(time.monotonic() - t0) / 60:.1f}분)", flush=True)
        if a.sql_out:
            for table, cols, rows in got.values(): sql += merge_sql(table, cols, rows)
        else:
            cur = conn.cursor()
            try:
                for table, cols, rows in got.values():
                    for st in merge_sql(table, cols, rows): cur.execute(st.replace("\nGO\n", ""))
                conn.commit()
            except Exception as ex:
                # ★ 넣다 실패한 법정동은 통째로 되돌리고(반쯤 넣지 않는다) 계속 간다 — 끝에 목록으로 말한다
                conn.rollback(); 실패.append((lw, "넣기 " + str(ex)[:120]))
                print(f"  ★ {lw} 넣기 실패 — 되돌림: {str(ex)[:160]}", flush=True)
    print(f"합: 표제부 {합.get('getSrTitleInfo', 0):,} · 총괄 {합.get('getSrRecapTitleInfo', 0):,}", flush=True)
    if 실패:
        print(f"★ 못 받은 법정동 {len(실패)}곳 (다시: --skip-loaded): " + ", ".join(x for x, _ in 실패), flush=True)
    sggs = sorted(set(a.sgg) | {lw[:5] for lw in lawds})   # 받은 게 없어도 요청한 시군구는 다시 묶는다(중간에 멈췄던 것)
    if a.sql_out:
        for g in sggs: sql.append(f"EXEC gold.usp_build_closed_site @sgg = '{g}';\nGO\n")
        io.open(a.sql_out, "w", encoding="utf-8").write("".join(sql)); print("SQL 파일:", a.sql_out); return
    cur = conn.cursor()
    for g in sggs:
        cur.execute("EXEC gold.usp_build_closed_site @sgg = %s", (g,)); print(f"철거 묶음 {g}:", cur.fetchone(), flush=True); conn.commit()
    conn.close()
    if 실패: sys.exit(2)


if __name__ == "__main__":
    main()
