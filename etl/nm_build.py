# -*- coding: utf-8 -*-
"""nm_build - 서비스DB(PostgreSQL teomoony) 의 매칭 테이블 스키마 nm 을 새로 만들고 바꿔 끼운다 (2026-10-27 사장님 "중복 데이터는 매칭 테이블 — 원본을 훼손하지 않으면 채용")
  ★ 원천 표 = 적재DB 원본 행 그대로(고치지 않는다): store(silver.semas_store + 뷰 gold.v_complex_poi 의 life · brand 규칙을 지금 정의에서 그대로 떼어 옴)
     · school · school_link · schoolinfo · schoolinfo_stat · school_zone · school_group · school_zone_link
  ★ 매칭 표 = 연결만(지금 적재DB 규칙 그대로): cpt(단지 가운데 점) · complex_pnu · complex_lawd · complex_zone(단지 → 통학구역 · 학교군, ST_Contains)
     · lawd_scope(법정동마다 '그 자료를 받았나' — 지금 상세의 EXISTS 와 같은 뜻)
  ★ nm_new 에 다 만든 뒤 한 번에 이름을 바꾼다(읽는 쪽은 옛 nm 아니면 새 nm 만 본다). 실패하면 옛 nm 이 그대로 남는다.
  py nm_build.py [--db teomoony] [--schema nm]"""
import argparse, re, time, psycopg
from svc_publish import env, ms_conn
ap = argparse.ArgumentParser(); ap.add_argument("--db", default="teomoony"); ap.add_argument("--schema", default="nm"); a = ap.parse_args()
E = env(); S = a.schema; N = S + "_new"
t = psycopg.connect(host="127.0.0.1", port=15432, dbname=a.db, user="teomoony", password=E["SVC_DB_PASSWORD"], autocommit=True)
ms = ms_conn(E).cursor()
T0 = time.time()
def 읽기(sql):
    ms.execute("SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; " + sql)
    while ms.description is None and ms.nextset(): pass
def 붓기(tb, cols, n=0):
    with t.cursor() as c, c.copy(f"COPY {N}.{tb} ({cols}) FROM STDIN") as cp:
        while True:
            rows = ms.fetchmany(50000)
            if not rows: break
            for r in rows: cp.write_row([int(x) if isinstance(x, bool) else x for x in r])
            n += len(rows)
    return n
def 찍기(tb, n, a0): print(f"  {tb}: {n:,}줄 · {time.time()-a0:.0f}초", flush=True)
t.execute("CREATE EXTENSION IF NOT EXISTS postgis")
t.execute(f"DROP SCHEMA IF EXISTS {N} CASCADE"); t.execute(f"CREATE SCHEMA {N}")
# 1 상가
a0 = time.time()
cur = ms_conn(E).cursor(); cur.execute("SELECT OBJECT_DEFINITION(OBJECT_ID('gold.v_complex_poi'))"); d = cur.fetchone()[0]
life = re.search(r"life\s*=\s*CASE.*?\n\s*END,", d, re.S).group(0).rstrip(',')
brand = re.sub(r"\s*FROM gold\.complex$", "", re.search(r"brand\s*=\s*CASE.*?\n\s*END\s*\n\s*FROM gold\.complex", d, re.S).group(0))
t.execute(f"""CREATE TABLE {N}.store (bizes_id text, bizes_nm text, brch_nm text, inds_lcls_cd text, inds_lcls_nm text, inds_mcls_cd text, inds_mcls_nm text,
              inds_scls_nm text, pnu text, lat float8, lon float8, life text, brand text)""")
읽기(f"""SELECT s.bizes_id, s.bizes_nm, s.brch_nm, s.inds_lcls_cd, s.inds_lcls_nm, s.inds_mcls_cd, s.inds_mcls_nm, s.inds_scls_nm,
             s.pnu, CAST(s.geog.Lat AS FLOAT), CAST(s.geog.Long AS FLOAT), {life}, {brand}
        FROM silver.semas_store s WHERE s.is_current = 1 AND s.geog IS NOT NULL""")
n = 붓기("store", "bizes_id,bizes_nm,brch_nm,inds_lcls_cd,inds_lcls_nm,inds_mcls_cd,inds_mcls_nm,inds_scls_nm,pnu,lat,lon,life,brand")
t.execute(f"ALTER TABLE {N}.store ADD COLUMN g geography(Point,4326)")
t.execute(f"UPDATE {N}.store SET g = ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography")
t.execute(f"CREATE INDEX ON {N}.store USING gist (g)"); 찍기("store", n, a0)
# 2 학교 원천 표(칸 그대로 — raw_json 만 뺀다)
PGT = {"int": "int", "bigint": "bigint", "smallint": "int", "tinyint": "int", "bit": "int", "decimal": "numeric", "numeric": "numeric",
       "float": "float8", "real": "float8", "date": "date", "datetime2": "timestamp", "datetime": "timestamp", "binary": "bytea", "varbinary": "bytea"}
for tb, src, gc, gk in [("school", "silver.school", "geog", "geography"), ("school_link", "gold.school_link", None, None),
                        ("schoolinfo", "silver.schoolinfo", None, None), ("schoolinfo_stat", "silver.schoolinfo_stat", None, None),
                        ("school_zone", "silver.school_zone", "geom", "geometry"), ("school_group", "silver.school_group", "geom", "geometry"),
                        ("school_zone_link", "silver.school_zone_link", None, None)]:
    a0 = time.time(); sch, nm = src.split(".")
    ms.execute("SELECT COLUMN_NAME, DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA=%s AND TABLE_NAME=%s ORDER BY ORDINAL_POSITION", (sch, nm))
    cols = [(c, ty) for c, ty in ms.fetchall() if c != "raw_json"]
    t.execute(f"CREATE TABLE {N}.{tb} (" + ", ".join(f'"{c}" ' + ("bytea" if c == gc else PGT.get(ty, "text")) for c, ty in cols) + ")")
    읽기("SELECT " + ", ".join(f"[{c}].STAsBinary()" if c == gc else f"[{c}]" for c, ty in cols) + f" FROM {src}")
    n = 붓기(tb, ", ".join(f'"{c}"' for c, ty in cols))
    if gc:
        t.execute(f"ALTER TABLE {N}.{tb} ADD COLUMN g {gk}")
        t.execute(f'UPDATE {N}.{tb} SET g = ' + (f'ST_GeogFromWKB("{gc}")' if gk == "geography" else f'ST_SetSRID(ST_GeomFromWKB("{gc}"), 4326)'))
        t.execute(f"CREATE INDEX ON {N}.{tb} USING gist (g)")
    찍기(tb, n, a0)
for ix in ["school_zone_link (hakgudo_id)", "school_link (school_id)", "schoolinfo (schul_code)", "schoolinfo_stat (schul_code, pban_yr DESC)",
           "school (school_id)", "schoolinfo (left(adrcd_cd, 5))", "school_zone (zone_sk)", "school_group (group_sk)"]:
    t.execute(f"CREATE INDEX ON {N}.{ix}")
# 3 매칭: 단지 점 · 필지 · 법정동
a0 = time.time()
t.execute(f"CREATE TABLE {N}.cpt (complex_id int PRIMARY KEY, lat float8, lon float8, sgg text, is_active int)")
읽기("SELECT complex_id, CAST(centroid_lat AS FLOAT), CAST(centroid_lng AS FLOAT), sigungu_cd, CAST(is_active AS INT) FROM gold.complex WHERE centroid_lat IS NOT NULL AND centroid_lng IS NOT NULL")
n = 붓기("cpt", "complex_id, lat, lon, sgg, is_active")
t.execute(f"ALTER TABLE {N}.cpt ADD COLUMN g geography(Point,4326)"); t.execute(f"UPDATE {N}.cpt SET g = ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography")
찍기("cpt", n, a0); a0 = time.time()
t.execute(f"CREATE TABLE {N}.complex_pnu (complex_id int, pnu text)"); 읽기("SELECT complex_id, pnu FROM gold.complex_pnu")
n = 붓기("complex_pnu", "complex_id, pnu"); t.execute(f"CREATE INDEX ON {N}.complex_pnu (complex_id, pnu)"); 찍기("complex_pnu", n, a0); a0 = time.time()
t.execute(f"CREATE TABLE {N}.complex_lawd (complex_id int PRIMARY KEY, lawd text)")
읽기("SELECT complex_id, sigungu_cd + bjdong_cd FROM gold.complex WHERE sigungu_cd IS NOT NULL AND bjdong_cd IS NOT NULL")
n = 붓기("complex_lawd", "complex_id, lawd"); 찍기("complex_lawd", n, a0)
# 4 매칭: 단지 → 통학구역 · 학교군 — 나눈 경계로 후보, 원래 경계로 ST_Contains 확인(적재DB STContains 와 같은 뜻)
a0 = time.time()
t.execute(f"""CREATE TABLE {N}.zone_sub AS SELECT 'E'::text kind, zone_sk sk, ST_Subdivide(g, 64) g FROM {N}.school_zone
              UNION ALL SELECT 'G', group_sk, ST_Subdivide(g, 64) FROM {N}.school_group""")
t.execute(f"CREATE INDEX ON {N}.zone_sub USING gist (g)"); t.execute(f"ANALYZE {N}.zone_sub"); t.execute(f"ANALYZE {N}.cpt")
t.execute(f"""CREATE TABLE {N}.complex_zone AS
  SELECT DISTINCT c.complex_id, s.kind, s.sk
    FROM {N}.cpt c JOIN {N}.zone_sub s ON ST_Intersects(s.g, ST_SetSRID(ST_MakePoint(c.lon, c.lat), 4326))
    LEFT JOIN {N}.school_zone z ON s.kind = 'E' AND z.zone_sk = s.sk
    LEFT JOIN {N}.school_group gq ON s.kind = 'G' AND gq.group_sk = s.sk
   WHERE ST_Contains(COALESCE(z.g, gq.g), ST_SetSRID(ST_MakePoint(c.lon, c.lat), 4326))""")
t.execute(f"CREATE INDEX ON {N}.complex_zone (complex_id)")
찍기("complex_zone", t.execute(f"SELECT count(*) FROM {N}.complex_zone").fetchone()[0], a0)
# 5 매칭: 법정동마다 자료를 받았나(지금 _q_scope 의 EXISTS 와 같은 뜻)
a0 = time.time()
def 모음(sql): 읽기(sql); return {x[0] for x in ms.fetchall() if x[0]}
축 = {"필지": "SELECT DISTINCT LEFT(pnu, 10) FROM silver.cadastral_parcel WHERE is_current = 1",
      "건물": "SELECT DISTINCT LEFT(pnu, 10) FROM silver.building_footprint WHERE is_current = 1",
      "인허가": "SELECT DISTINCT LEFT(pnu, 10) FROM silver.arch_permit WHERE is_current = 1",
      "kapt": "SELECT DISTINCT bjd_code FROM silver.kapt_complex WHERE is_current = 1",
      "주택가격": "SELECT DISTINCT LEFT(pnu, 10) FROM silver.bld_hsprc WHERE is_current = 1",
      "전유부": "SELECT DISTINCT LEFT(pnu, 10) FROM silver.bld_expos WHERE is_current = 1",
      "층별": "SELECT DISTINCT t2.sigungu_cd + t2.bjdong_cd FROM silver.bld_flr_outline f JOIN silver.bld_title t2 ON t2.mgm_bldrgst_pk = f.mgm_bldrgst_pk AND t2.is_current = 1 WHERE f.is_current = 1"}
있음 = {k: 모음(q) for k, q in 축.items()}
관리비구 = 모음("SELECT DISTINCT LEFT(k2.bjd_code, 5) FROM silver.kapt_cost kc JOIN silver.kapt_complex k2 ON k2.kapt_code = kc.kapt_code AND k2.is_current = 1")
lawds = {x[0] for x in t.execute(f"SELECT DISTINCT lawd FROM {N}.complex_lawd").fetchall()}
t.execute(f'CREATE TABLE {N}.lawd_scope (lawd text PRIMARY KEY, "필지" int, "건물" int, "인허가" int, kapt int, "관리비구" int, "주택가격" int, "전유부" int, "층별" int)')
with t.cursor() as c, c.copy(f"COPY {N}.lawd_scope FROM STDIN") as cp:
    for L in lawds:
        cp.write_row([L] + [1 if L in 있음[k] else 0 for k in ("필지", "건물", "인허가", "kapt")] + [1 if L[:5] in 관리비구 else 0]
                     + [1 if L in 있음[k] else 0 for k in ("주택가격", "전유부", "층별")])
찍기("lawd_scope", len(lawds), a0)
t.execute(f"ANALYZE")  # 통계
# 6 바꿔 끼우기 — 짧게, 잠금 3초 제한(svc_layers 와 같은 이유)
for 번 in range(20):
    try:
        with t.transaction():
            t.execute("SET LOCAL lock_timeout = '3s'")
            t.execute(f"DROP SCHEMA IF EXISTS {S}_old CASCADE")
            if t.execute("SELECT 1 FROM pg_namespace WHERE nspname = %s", (S,)).fetchone(): t.execute(f"ALTER SCHEMA {S} RENAME TO {S}_old")
            t.execute(f"ALTER SCHEMA {N} RENAME TO {S}")
        break
    except psycopg.errors.LockNotAvailable: time.sleep(5)
else: raise RuntimeError("nm 바꿔 끼우기 잠금을 못 잡음")
t.execute(f"DROP SCHEMA IF EXISTS {S}_old CASCADE")
t.execute("""CREATE TABLE IF NOT EXISTS svc.nm_state (built_at timestamptz, secs real)""") if a.db == "teomoony" else None
if a.db == "teomoony": t.execute("INSERT INTO svc.nm_state VALUES (now(), %s)", (time.time() - T0,))
print(f"nm 끝 · {time.time()-T0:.0f}초 · 크기 {t.execute(f'SELECT pg_size_pretty(sum(pg_total_relation_size(c.oid))) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = %s', (S,)).fetchone()[0]}", flush=True)
