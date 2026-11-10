#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""svc_pub_urls - 주소 단위 응답을 서비스DB 로 미리 담는다 (2026-11-01, 서비스DB 분리 1묶음)
  py svc_pub_urls.py                 # 모든 묶음(지문이 같으면 건너뜀)
  py svc_pub_urls.py --only areas,redev_detail --force areas
★ 단지 상세(svc_publish)와 같은 방식: **같은 서버 · 같은 주소**에서 받은 몸을 그대로 담는다(?_svcbuild=1 로 서비스DB 길을 비켜 적재DB 경로가 답하게).
  → 화면과 값이 같다는 게 처음부터 보장된다. 담는 키 = 경로 + 물음표 칸을 이름순으로 세운 것(svc.js 공개응답이 같은 규칙으로 찾는다).
★ 묶음마다 '키 목록 SQL'(적재DB) 로 주소를 다 만든다 → 새 목록에 없는 옛 주소는 지운다(그 묶음 것만).
★ 400 · 404 도 원 서버가 그렇게 답한 것이라 그대로 담는다. 5xx · 끊김은 담지 않는다(옛 값을 남김)."""
import argparse, gzip, hashlib, json, sys, time, urllib.parse, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor
from etl_batch import bounded_map
from svc_publish import env, ms_conn, pg_conn, WEB

U = "SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;\n"
# (묶음, 지문 SQL(None = 매번), 키 SQL(줄마다 주소 하나 — 첫 칸), 일꾼 수)
SETS = [
  ("areas", """SELECT CONCAT((SELECT CONCAT(COUNT_BIG(*), '/', CHECKSUM_AGG(CHECKSUM(lawd_cd, sido_nm, sgg_nm, emd_nm, ri_nm, is_abolished))) FROM meta.lawd_code), '|',
                         (SELECT CONCAT(COUNT_BIG(*), '/', MAX(valid_from), '/', MAX(valid_to)) FROM silver.lawd_boundary), '|',
                         (SELECT CONCAT(COUNT_BIG(*), '/', MAX(year)) FROM silver.adm_boundary), '|',
                         (SELECT CONCAT(COUNT_BIG(*), '/', MAX(valid_from), '/', MAX(valid_to)) FROM silver.ri_boundary), '|',
                         (SELECT COUNT_BIG(*) FROM gold.complex))""",
   U + """SELECT u = '/api/areas/sido'
          UNION ALL SELECT DISTINCT '/api/areas/sgg?sido=' + sido_cd FROM meta.lawd_code WHERE sgg_nm IS NULL AND emd_nm IS NULL AND ri_nm IS NULL AND is_abolished = 0
          UNION ALL SELECT DISTINCT '/api/areas/dongs?kind=' + k.k + '&sgg=' + l.sgg_cd FROM meta.lawd_code l CROSS JOIN (VALUES ('lawd'), ('adm')) k(k)
                     WHERE l.sgg_nm IS NOT NULL AND l.emd_nm IS NULL AND l.ri_nm IS NULL AND l.is_abolished = 0 AND l.sgg_cd IS NOT NULL
          UNION ALL SELECT DISTINCT '/api/areas/dongs?sgg=' + l.sgg_cd FROM meta.lawd_code l
                     WHERE l.sgg_nm IS NOT NULL AND l.emd_nm IS NULL AND l.ri_nm IS NULL AND l.is_abolished = 0 AND l.sgg_cd IS NOT NULL
          UNION ALL SELECT DISTINCT '/api/areas/ris?emd=' + LEFT(lawd_cd, 8) + '00' FROM meta.lawd_code WHERE ri_nm IS NOT NULL AND is_abolished = 0""", 4),
  ("coverage", None, "SELECT u = '/api/coverage'", 1),
  ("redev_detail", "SELECT CONCAT(COUNT_BIG(*), '/', MAX(valid_from), '/', MAX(valid_to), '/', (SELECT COUNT_BIG(*) FROM silver.applyhome_pblanc), '/', (SELECT COUNT_BIG(*) FROM gold.redev_plan_link), '/', (SELECT COUNT_BIG(*) FROM gold.complex)) FROM silver.redev_zone",
   U + """SELECT '/api/redev/' + present_sn + '/detail' FROM silver.redev_zone WHERE is_current = 1
          UNION ALL SELECT '/api/redev/' + present_sn FROM silver.redev_zone WHERE is_current = 1""", 3),
]
# ---- 2묶음(11-01): 분양·청약 · 경계 · 학원 · 학교 · 유치원 · 어린이집 · 공사 전 상세 ----
# 다섯째 칸 = 선택: every(시간 — 지문이 바뀌어도 이보다 자주 안 함) · wild(빈 응답 본보기 SQL: 첫 칸 = 주소, 키는 그 값만 '*') · more(분양권 전부 ?sv=all 도)
AH_FP = """SELECT CONCAT((SELECT CONCAT(COUNT_BIG(*), '/', MAX(rcrit_pblanc_de), '/', CHECKSUM_AGG(CHECKSUM(house_manage_no, pblanc_no, pnu, tot_suply))) FROM silver.applyhome_pblanc), '|',
                     (SELECT CONCAT(COUNT_BIG(*), '/', CHECKSUM_AGG(CHECKSUM(house_manage_no, pblanc_no, complex_id, kapt_code, 근거))) FROM gold.applyhome_link), '|',
                     (SELECT COUNT_BIG(*) FROM silver.applyhome_mdl), '|', (SELECT COUNT_BIG(*) FROM silver.applyhome_cmpet), '|', (SELECT COUNT_BIG(*) FROM silver.applyhome_score), '|',
                     (SELECT CONCAT(COUNT_BIG(*), '/', MAX(trade_sk), '/', SUM(CAST(ISNULL(is_canceled, 0) AS INT))) FROM silver.rtms_trade WHERE trade_kind LIKE 'SILV%'), '|',
                     (SELECT CONCAT(COUNT_BIG(*), '/', CHECKSUM_AGG(CHECKSUM(complex_id, kapt_code))) FROM gold.complex_kapt), '|',
                     (SELECT COUNT_BIG(*) FROM gold.complex), '|', (SELECT CONCAT(COUNT_BIG(*), '/', CHECKSUM_AGG(CHECKSUM(complex_id, 원문pk, 상태))) FROM gold.pre_complex))"""
AH_C = """WITH sp AS (SELECT DISTINCT match_pnu FROM silver.rtms_trade WHERE trade_kind LIKE 'SILV%' AND match_pnu IS NOT NULL),
       c AS (SELECT complex_id FROM gold.applyhome_link WHERE complex_id IS NOT NULL
             UNION SELECT cp.complex_id FROM gold.complex_pnu cp JOIN sp ON sp.match_pnu = cp.pnu
             UNION SELECT ck.complex_id FROM gold.complex_kapt ck JOIN silver.kapt_complex k ON k.kapt_code = ck.kapt_code AND k.is_current = 1 JOIN sp ON sp.match_pnu = k.pnu)"""
SETS += [
  # 단지 분양·청약 탭 — 공고가 이어졌거나 그 필지(· 이어진 K-apt 지번)에 분양권 거래가 있는 단지만 담는다. 나머지는 빈 응답(본보기 하나)
  ("applyhome_c", AH_FP, U + AH_C + " SELECT '/api/applyhome?complex_id=' + CAST(complex_id AS VARCHAR(12)) FROM c", 3,
   {"heavy": True, "every": 6, "more": True,
    "wild": U + AH_C + " SELECT TOP 1 '/api/applyhome?complex_id=' + CAST(g.complex_id AS VARCHAR(12)) FROM gold.complex g WHERE NOT EXISTS (SELECT 1 FROM c WHERE c.complex_id = g.complex_id) ORDER BY g.complex_id"}),
  ("applyhome_k", AH_FP, U + "SELECT DISTINCT '/api/applyhome?kapt_code=' + kapt_code FROM gold.applyhome_link WHERE kapt_code IS NOT NULL", 2,
   {"heavy": True, "every": 6, "more": True,
    "wild": U + "SELECT TOP 1 '/api/applyhome?kapt_code=' + k.kapt_code FROM silver.kapt_complex k WHERE k.is_current = 1 AND NOT EXISTS (SELECT 1 FROM gold.applyhome_link l WHERE l.kapt_code = k.kapt_code) ORDER BY k.kapt_code"}),
  ("applyhome_h", AH_FP, U + """SELECT DISTINCT '/api/applyhome?house=' + house_manage_no FROM silver.applyhome_pblanc
          UNION ALL SELECT DISTINCT '/api/applyhome/' + house_manage_no + '/where' FROM silver.applyhome_pblanc WHERE house_manage_no NOT LIKE '%[^0-9]%'
          UNION ALL SELECT DISTINCT '/api/precomplex-ah/' + house_manage_no FROM silver.applyhome_pblanc WHERE house_manage_no NOT LIKE '%[^0-9]%'""", 3,
   {"heavy": True, "every": 6, "more": True}),
  ("applyhome_d", AH_FP, U + """SELECT DISTINCT '/api/applyhome/dong/' + lawd_cd FROM meta.lawd_code WHERE emd_nm IS NOT NULL AND is_abolished = 0 AND LEN(lawd_cd) = 10
          UNION SELECT DISTINCT '/api/applyhome/dong/' + lawd_cd FROM silver.applyhome_pblanc WHERE LEN(lawd_cd) = 10""", 3, {"heavy": True, "every": 24}),
  # 법정동 · 리 경계(+ 그 동 셈) · 행정동 경계
  ("lawd_geo", """SELECT CONCAT((SELECT CONCAT(COUNT_BIG(*), '/', MAX(valid_from), '/', MAX(valid_to)) FROM silver.lawd_boundary), '|',
                                (SELECT CONCAT(COUNT_BIG(*), '/', MAX(valid_from), '/', MAX(valid_to)) FROM silver.ri_boundary), '|',
                                (SELECT CONCAT(COUNT_BIG(*), '/', SUM(CAST(trade_cnt AS BIGINT)), '/', SUM(CAST(complex_cnt AS BIGINT))) FROM gold.v_lawd_map))""",
   U + """SELECT '/api/lawds/' + lawd_cd + '/geo' FROM silver.lawd_boundary WHERE is_current = 1 AND lawd_cd LIKE '%00'
          UNION SELECT '/api/lawds/' + lawd_cd + '/geo' FROM silver.ri_boundary WHERE is_current = 1 AND lawd_cd NOT LIKE '%00'""", 3, {"heavy": True, "every": 24}),
  ("adm_geo", """SELECT CONCAT((SELECT CONCAT(COUNT_BIG(*), '/', MAX(year)) FROM silver.adm_boundary), '|',
                               (SELECT CONCAT(COUNT_BIG(*), '/', CHECKSUM_AGG(CHECKSUM(adm_cd_sgis, year, 행정동코드, 표시, 현행))) FROM gold.adm_link))""",
   U + "SELECT DISTINCT '/api/adms/' + adm_cd_sgis + '/geo' FROM silver.adm_boundary", 3, {"heavy": True, "every": 24}),
  # 학원 · 학교 · 유치원 · 어린이집 상세(물음표 없는 것 — ?cid= 의 거리는 svc.js 가 붙인다)
  ("academy", "SELECT CONCAT(COUNT_BIG(*), '/', MAX(academy_sk)) FROM silver.academy",
   U + "SELECT DISTINCT '/api/academy/' + aca_asnum FROM silver.academy WHERE is_current = 1 AND aca_asnum NOT LIKE '%[^0-9A-Za-z]%'", 3, {"heavy": True, "every": 24}),
  ("school", None, U + "SELECT '/api/school/' + school_id FROM silver.school WHERE school_id NOT LIKE '%[^0-9A-Za-z]%'", 2, {"heavy": True, "every": 168}),
  ("kinder", None, U + "SELECT '/api/kinder/' + kinder_cd FROM silver.kindergarten WHERE kinder_cd NOT LIKE '%[^0-9A-Za-z-]%'", 2, {"heavy": True, "every": 168}),
  ("childcare", None, U + "SELECT DISTINCT '/api/childcare/' + stcode FROM silver.childcare WHERE is_current = 1 AND stcode NOT LIKE '%[^0-9A-Za-z]%'", 2, {"heavy": True, "every": 168}),
  # 공사 중 · 승인 · 대장 전 신축(K-apt) 상세
  ("pre", """SELECT CONCAT((SELECT CONCAT(COUNT_BIG(*), '/', CHECKSUM_AGG(CHECKSUM(*))) FROM gold.pre_build), '|',
                           (SELECT CONCAT(COUNT_BIG(*), '/', CHECKSUM_AGG(CHECKSUM(hp_pk, 이름, 세대, 승인일, 착공일, 사용검사예정일, 상태, lat, lng))) FROM gold.house_plan), '|',
                           (SELECT CONCAT(COUNT_BIG(*), '/', CHECKSUM_AGG(CHECKSUM(complex_id, 종류, 원문pk, 상태, 이동_complex_id))) FROM gold.pre_complex))""",
   U + """SELECT '/api/prebuilds/' + pk FROM gold.pre_build WHERE pk NOT LIKE '%[^0-9A-Za-z_-]%'
          UNION ALL SELECT '/api/houseplans/' + hp_pk FROM gold.house_plan WHERE hp_pk NOT LIKE '%[^0-9A-Za-z_-]%'
          UNION ALL SELECT '/api/precomplex/' + RTRIM(종류) + '/' + 원문pk FROM gold.pre_complex WHERE 원문pk NOT LIKE '%[^0-9A-Za-z_-]%'""", 2, {"every": 1}),
  ("newbuild", "SELECT CONCAT(COUNT_BIG(*), '/', CHECKSUM_AGG(CHECKSUM(kapt_code, 거래, 최고가))) FROM gold.v_newbuild",
   U + "SELECT '/api/newbuilds/' + kapt_code FROM gold.v_newbuild WHERE kapt_code NOT LIKE '%[^0-9A-Za-z]%'", 2, {"heavy": True, "every": 6}),
]



def 키(u):
    """주소 → 담는 키: 경로 + 물음표 칸 이름순(_svc* · _t 는 뺌). svc.js 공개응답의 키()와 같아야 한다."""
    p = urllib.parse.urlsplit(u)
    q = sorted((k, v) for k, v in urllib.parse.parse_qsl(p.query, keep_blank_values=True) if not k.startswith("_svc") and k != "_t")
    return p.path + ("?" + urllib.parse.urlencode(q, quote_via=urllib.parse.quote) if q else "")


def 받기(u, timeout=180):
    sep = "&" if "?" in u else "?"
    req = urllib.request.Request(WEB + u + sep + "_svcbuild=1", headers={"Accept-Encoding": "identity"})
    for a in range(3):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.status, r.read()
        except urllib.error.HTTPError as h:
            if h.code in (400, 404): return h.code, h.read()
            if a == 2: return None, None
        except Exception:
            if a == 2: return None, None
        time.sleep(2 * (a + 1))


def run_set(ms, pg, name, fp_sql, key_sql, workers, force, opt=None):
    opt = opt or {}
    with pg.cursor() as c:
        c.execute("SELECT fingerprint, extract(epoch FROM now() - built_at) / 3600 FROM svc.pub_state WHERE name = %s", (name,)); r = c.fetchone()
    if r and opt.get("every") and r[1] is not None and r[1] < opt["every"] and r[0] is not None and not force:
        print(f"  {name}: {opt['every']}시간마다 — 아직 {r[1]:.1f}시간", flush=True); return
    fp = None
    if fp_sql:
        cur = ms.cursor(); cur.execute(fp_sql); fp = str(cur.fetchone()[0])
        if r and r[0] == fp and not force:
            print(f"  {name}: 원천 그대로 — 건너뜀", flush=True); return
    본보기 = None
    if opt.get("wild"):   # 빈 응답 본보기 — 목록 밖 아무 하나를 받아 '*' 키로 담는다(목록이 다 담겼을 때만 — 아래)
        cur = ms.cursor(); cur.execute(opt["wild"])
        while cur.description is None and cur.nextset(): pass
        x = cur.fetchone(); 본보기 = x[0] if x else None
    cur = ms.cursor(); cur.execute(key_sql)
    while cur.description is None and cur.nextset(): pass
    with pg.cursor() as c:
        c.execute("DROP TABLE IF EXISTS pg_temp.pub_url_source, pg_temp.pub_urls, pg_temp.pub_url_keys")
        c.execute('CREATE TEMP TABLE pub_url_source (url text COLLATE "C") ON COMMIT DROP')
        with c.copy("COPY pub_url_source FROM STDIN") as cp:
            while rows := cur.fetchmany(5000):
                for row in rows:
                    if row[0]:
                        cp.write_row((row[0],))
        c.execute("CREATE TEMP TABLE pub_urls AS SELECT DISTINCT url FROM pub_url_source")
        c.execute("ALTER TABLE pub_urls ADD PRIMARY KEY (url)")
        c.execute("CREATE TEMP TABLE pub_url_keys (url text PRIMARY KEY)")
    pg.commit()
    t = time.time(); 담음 = 실패 = 주소수 = 0

    def 주소들():
        after = ""
        while True:
            with pg.cursor() as c:
                c.execute("SELECT url FROM pub_urls WHERE url > %s ORDER BY url LIMIT 500", (after,))
                page = c.fetchall()
            pg.commit()
            if not page:
                return
            after = page[-1][0]
            for (u,) in page:
                yield u

    def 하나(u):
        st, body = 받기(u)
        더 = None
        if opt.get("more") and st == 200 and body:   # 분양권이 처음 40줄보다 많으면 화면이 '전부' 를 부른다(?sv=all) — 그것도 담는다
            try:
                j = json.loads(body.decode("utf-8")); n = j.get("분양권수") or {}
                if len(j.get("분양권") or []) < (int(n.get("건수") or 0) + int(n.get("취소") or 0)):
                    u2 = u + ("&" if "?" in u else "?") + "sv=all"; 더 = (u2,) + 받기(u2)
            except Exception: pass
        return u, st, body, 더

    def 담기(k, st, body):
        gz = gzip.compress(body, 6)
        with pg.cursor() as c:
            c.execute("INSERT INTO pub_url_keys VALUES (%s) ON CONFLICT DO NOTHING", (k,))
            c.execute("""INSERT INTO svc.resp_pub (url, set_name, status, body_gz, sha, bytes, at) VALUES (%s, %s, %s, %s, %s, %s, now())
                         ON CONFLICT (url) DO UPDATE SET set_name = EXCLUDED.set_name, status = EXCLUDED.status, body_gz = EXCLUDED.body_gz,
                                                         sha = EXCLUDED.sha, bytes = EXCLUDED.bytes,
                                                         at = CASE WHEN svc.resp_pub.sha = EXCLUDED.sha THEN svc.resp_pub.at ELSE now() END""",
                      (k, name, st, gz, hashlib.sha256(body).hexdigest(), len(body)))
        pg.commit()

    def 쓸만(st, body):
        if st is None or body is None: return False
        try:
            j = json.loads(body.decode("utf-8"))
            return not (st == 200 and isinstance(j, dict) and j.get("error"))
        except Exception:
            return False
    with ThreadPoolExecutor(max_workers=workers) as ex:
        for u, st, body, 더 in bounded_map(ex, 하나, 주소들(), workers * 4):
            주소수 += 1
            k = 키(u)
            if not 쓸만(st, body): 실패 += 1; continue
            if 더:
                if 쓸만(더[1], 더[2]): 담기(키(더[0]), 더[1], 더[2])
                else: 실패 += 1
            담기(k, st, body); 담음 += 1
            if 담음 % 5000 == 0: print(f"    {name}: {담음:,} · {time.time() - t:.0f}초", flush=True)
    if 본보기 and not 실패:
        st, body = 받기(본보기)
        if 쓸만(st, body):
            from urllib.parse import urlsplit, parse_qsl
            q = parse_qsl(urlsplit(본보기).query)
            wk = urlsplit(본보기).path + "?" + q[0][0] + "=*"
            담기(wk, st, body)
        else: 실패 += 1
    지움 = 0
    if not 실패:   # 다 받았을 때만 옛 주소를 지운다(일부 실패면 옛 값을 남긴다)
        with pg.cursor() as c:
            c.execute("""DELETE FROM svc.resp_pub p WHERE p.set_name = %s
                         AND NOT EXISTS (SELECT 1 FROM pub_url_keys k WHERE k.url = p.url)""", (name,))
            지움 = c.rowcount
        pg.commit()
    with pg.cursor() as c:
        c.execute("""INSERT INTO svc.pub_state VALUES (%s, %s, %s, %s, now(), %s)
                     ON CONFLICT (name) DO UPDATE SET fingerprint = EXCLUDED.fingerprint, urls = EXCLUDED.urls, failed = EXCLUDED.failed,
                                                      built_at = EXCLUDED.built_at, secs = EXCLUDED.secs""",
                  (name, fp if not 실패 else None, 주소수, 실패, time.time() - t))
        c.execute("DROP TABLE pub_urls, pub_url_keys")
    pg.commit()
    print(f"  {name}: 주소 {주소수:,} · 담음 {담음:,} · 실패 {실패:,} · 지움 {지움:,} · {time.time() - t:.0f}초", flush=True)


def run(ms, pg, only=(), force=(), heavy=False):
    """heavy=False(매시 발행이 부름): 가벼운 묶음만. 무거운 묶음(분양 · 경계 · 학원 · 학교 …)은 따로 6시간마다(cl-svc-pub-par --heavy) — 매시 발행을 오래 붙잡지 않게"""
    with pg.cursor() as c:
        c.execute("""CREATE TABLE IF NOT EXISTS svc.resp_pub (url text PRIMARY KEY, set_name text NOT NULL, status int NOT NULL,
                     body_gz bytea NOT NULL, sha text, bytes int, at timestamptz NOT NULL DEFAULT now())""")
        c.execute("CREATE INDEX IF NOT EXISTS ix_resp_pub_set ON svc.resp_pub (set_name)")
        c.execute("""CREATE TABLE IF NOT EXISTS svc.pub_state (name text PRIMARY KEY, fingerprint text, urls int, failed int,
                     built_at timestamptz, secs real)""")
    pg.commit()
    for spec in SETS:
        name, fp_sql, key_sql, w = spec[:4]; opt = spec[4] if len(spec) > 4 else {}
        if only and name not in only: continue
        if not only and bool(opt.get("heavy")) != heavy: continue
        try:
            run_set(ms, pg, name, fp_sql, key_sql, w, name in force or "all" in force, opt)
        except Exception as ex:   # 한 묶음이 실패해도 다음 묶음은 돈다
            pg.rollback(); print(f"  !! {name} 실패: {type(ex).__name__}: {str(ex)[:200]}", flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default=""); ap.add_argument("--force", default=""); ap.add_argument("--heavy", action="store_true")
    a = ap.parse_args()
    e = env(); ms = ms_conn(e); pg = pg_conn(e)
    t = time.time()
    run(ms, pg, set(filter(None, a.only.split(","))), set(filter(None, a.force.split(","))), a.heavy)
    print(f"주소 묶음 끝 · {time.time() - t:.0f}초")


if __name__ == "__main__":
    main()
