# -*- coding: utf-8 -*-
"""norm_build - 개발판(5174) 용 시험 DB teomoony_test 를 전국으로 채운다 (2026-10-27 사장님 "프론트도 개발로 만들고 그 디비를 바라보게")
  cpt         : 단지 가운데 점(gold.complex 그대로 · is_active · 시군구)
  complex_pnu : 단지 ↔ 필지(gold.complex_pnu 그대로 — 상가 '단지 안' 판정)
  complex_zone: 단지 → 통학구역(E) · 학교군(G) 행 — 나눈 경계(ST_Subdivide)로 후보를 좁히고 **원래 경계로 ST_Contains 확인**(적재DB STContains 와 같은 뜻)
  상가 · 학교 원천 표는 norm_test.py / norm_test2.py setup 이 이미 만들었다."""
import time
from svc_publish import env, ms_conn
from norm_test import pgc
E = env(); t = pgc("teomoony_test"); ms = ms_conn(E).cursor()
def 옮김(name, ddl, sql, cols):
    a = time.time()
    t.execute(f"DROP TABLE IF EXISTS {name}_new"); t.execute(ddl.format(t=f"{name}_new"))
    ms.execute("SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; " + sql)
    while ms.description is None and ms.nextset(): pass
    n = 0
    with t.cursor() as c, c.copy(f"COPY {name}_new ({cols}) FROM STDIN") as cp:
        while True:
            rows = ms.fetchmany(50000)
            if not rows: break
            for r in rows: cp.write_row([int(x) if isinstance(x, bool) else x for x in r])
            n += len(rows)
    print(f"  {name}: {n:,}줄 · {time.time()-a:.0f}초", flush=True); return n
옮김("cpt", "CREATE TABLE {t} (complex_id int PRIMARY KEY, lat float8, lon float8, sgg text, is_active int)",
     "SELECT complex_id, CAST(centroid_lat AS FLOAT), CAST(centroid_lng AS FLOAT), sigungu_cd, CAST(is_active AS INT) FROM gold.complex WHERE centroid_lat IS NOT NULL AND centroid_lng IS NOT NULL",
     "complex_id, lat, lon, sgg, is_active")
t.execute("ALTER TABLE cpt_new ADD COLUMN g geography(Point,4326)")
t.execute("UPDATE cpt_new SET g = ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography")
t.execute("DROP TABLE IF EXISTS cpt"); t.execute("ALTER TABLE cpt_new RENAME TO cpt"); t.execute("ALTER INDEX cpt_new_pkey RENAME TO cpt_pkey"); t.execute("ANALYZE cpt")
옮김("complex_pnu", "CREATE TABLE {t} (complex_id int, pnu text)", "SELECT complex_id, pnu FROM gold.complex_pnu", "complex_id, pnu")
t.execute("CREATE INDEX ON complex_pnu_new (complex_id, pnu)")
t.execute("DROP TABLE IF EXISTS complex_pnu"); t.execute("ALTER TABLE complex_pnu_new RENAME TO complex_pnu"); t.execute("ANALYZE complex_pnu")
a = time.time()
t.execute("DROP TABLE IF EXISTS complex_zone_new")
t.execute("""CREATE TABLE complex_zone_new AS
  SELECT DISTINCT c.complex_id, s.kind, s.sk
    FROM cpt c JOIN zone_sub s ON ST_Intersects(s.g, ST_SetSRID(ST_MakePoint(c.lon, c.lat), 4326))
    LEFT JOIN school_zone z ON s.kind = 'E' AND z.zone_sk = s.sk
    LEFT JOIN school_group gq ON s.kind = 'G' AND gq.group_sk = s.sk
   WHERE ST_Contains(COALESCE(z.g, gq.g), ST_SetSRID(ST_MakePoint(c.lon, c.lat), 4326))""")
t.execute("CREATE INDEX ON complex_zone_new (complex_id)")
t.execute("DROP TABLE IF EXISTS complex_zone"); t.execute("ALTER TABLE complex_zone_new RENAME TO complex_zone"); t.execute("ANALYZE complex_zone")
print(f"  complex_zone(매칭): {t.execute('SELECT count(*) FROM complex_zone').fetchone()[0]:,}줄 · {time.time()-a:.0f}초", flush=True)
print("  DB 크기:", t.execute("SELECT pg_size_pretty(pg_database_size('teomoony_test'))").fetchone()[0])
