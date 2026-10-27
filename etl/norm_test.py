# -*- coding: utf-8 -*-
"""norm_test - 서비스DB 정규화(원천 표 + 매칭 표) 성능 시험 (2026-10-27, 사장님 "테스트 DB 를 하나 더 파서 테스트해도 돼")
  ★ 시험 전용 DB teomoony_test(같은 PostgreSQL) 에만 쓴다 — 서비스DB(teomoony) · 적재DB 는 읽기만.
  ★ 거리 정수: 적재DB 는 CAST(AS INT) = 버림 → 여기도 trunc (처음에 ::int(반올림)로 해 1m 씩 어긋났다)
  1단계 = 주변 상가(poi · poiSum · poiBrand · poiLife). 지금 적재DB 의 gold.v_complex_poi 와 **같은 정의**로:
    상가 한 줄 = 원본(silver.semas_store) 그대로 + life · brand(뷰의 CASE 를 지금 정의에서 그대로 떼어 옴 — 따로 적지 않는다).
    거리 = 단지 가운데 점 ↔ 상가 점 직선(geography). on_site = 상가 pnu 가 단지 필지(complex_pnu) 중 하나.
  py norm_test.py setup   — DB · 표 만들기(상가 전국 · 단지 표본 점 · 표본의 필지)
  py norm_test.py bench   — 표본 단지마다 4개 질의: 시험DB(PostGIS) vs 적재DB(지금 경로) · 결과 대조 · 시간"""
import os, re, sys, time, random, statistics, json
import psycopg
from svc_publish import env, ms_conn
E = env()
def pgc(db): return psycopg.connect(host="127.0.0.1", port=15432, dbname=db, user="teomoony", password=E["SVC_DB_PASSWORD"], autocommit=True)

def 뷰조각():
    cur = ms_conn(E).cursor(); cur.execute("SELECT OBJECT_DEFINITION(OBJECT_ID('gold.v_complex_poi'))"); d = cur.fetchone()[0]
    life = re.search(r"life\s*=\s*CASE.*?\n\s*END,", d, re.S).group(0).rstrip(',')
    brand = re.search(r"brand\s*=\s*CASE.*?\n\s*END\s*\n\s*FROM gold\.complex", d, re.S).group(0)
    brand = re.sub(r"\s*FROM gold\.complex$", "", brand)
    return life, brand

def setup():
    with pgc("teomoony") as c:
        if not c.execute("SELECT 1 FROM pg_database WHERE datname='teomoony_test'").fetchone():
            c.execute("CREATE DATABASE teomoony_test"); print("teomoony_test 만듦", flush=True)
    t = pgc("teomoony_test")
    t.execute("CREATE EXTENSION IF NOT EXISTS postgis")
    life, brand = 뷰조각()
    ms = ms_conn(E).cursor()
    a = time.time()
    ms.execute(f"""SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
      SELECT s.bizes_id, s.bizes_nm, s.brch_nm, s.inds_lcls_cd, s.inds_lcls_nm, s.inds_mcls_cd, s.inds_mcls_nm, s.inds_scls_nm,
             s.pnu, CAST(s.geog.Lat AS FLOAT), CAST(s.geog.Long AS FLOAT), {life}, {brand}
        FROM silver.semas_store s WHERE s.is_current = 1 AND s.geog IS NOT NULL""")
    t.execute("DROP TABLE IF EXISTS store")
    t.execute("""CREATE TABLE store (bizes_id text PRIMARY KEY, bizes_nm text, brch_nm text, inds_lcls_cd text, inds_lcls_nm text,
                 inds_mcls_cd text, inds_mcls_nm text, inds_scls_nm text, pnu text, lat float8, lon float8, life text, brand text, g geography(Point,4326))""")
    n = 0
    with t.cursor() as c, c.copy("COPY store (bizes_id,bizes_nm,brch_nm,inds_lcls_cd,inds_lcls_nm,inds_mcls_cd,inds_mcls_nm,inds_scls_nm,pnu,lat,lon,life,brand) FROM STDIN") as cp:
        while True:
            rows = ms.fetchmany(20000)
            if not rows: break
            for r in rows: cp.write_row(r)
            n += len(rows)
    t.execute("UPDATE store SET g = ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography")
    t.execute("CREATE INDEX store_g ON store USING gist (g)"); t.execute("ANALYZE store")
    print(f"상가 {n:,}줄 · {time.time()-a:.0f}초", flush=True)
    # 표본: 작은 건물(세대 < 20) — 서울 500 · 서울 밖 500 (좌표 있는 지금 단지)
    ms.execute("""SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
      SELECT TOP 500 complex_id, CAST(centroid_lat AS FLOAT), CAST(centroid_lng AS FLOAT), sigungu_cd FROM gold.complex
       WHERE merged_into IS NULL AND is_active = 1 AND centroid_lat IS NOT NULL AND ISNULL(hhld_cnt_sum,0) < 20 AND sigungu_cd LIKE '11%' ORDER BY NEWID();
      SELECT TOP 500 complex_id, CAST(centroid_lat AS FLOAT), CAST(centroid_lng AS FLOAT), sigungu_cd FROM gold.complex
       WHERE merged_into IS NULL AND is_active = 1 AND centroid_lat IS NOT NULL AND ISNULL(hhld_cnt_sum,0) < 20 AND sigungu_cd NOT LIKE '11%' ORDER BY NEWID();""")
    s = ms.fetchall(); ms.nextset(); s += ms.fetchall()
    t.execute("DROP TABLE IF EXISTS cpt"); t.execute("CREATE TABLE cpt (complex_id int PRIMARY KEY, lat float8, lon float8, sgg text, g geography(Point,4326))")
    with t.cursor() as c, c.copy("COPY cpt (complex_id,lat,lon,sgg) FROM STDIN") as cp:
        for r in s: cp.write_row(r)
    t.execute("UPDATE cpt SET g = ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography")
    ids = ",".join(str(r[0]) for r in s)
    ms.execute(f"SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; SELECT complex_id, pnu FROM gold.complex_pnu WHERE complex_id IN ({ids})")
    p = ms.fetchall()
    t.execute("DROP TABLE IF EXISTS complex_pnu"); t.execute("CREATE TABLE complex_pnu (complex_id int, pnu text, PRIMARY KEY (complex_id, pnu))")
    with t.cursor() as c, c.copy("COPY complex_pnu FROM STDIN") as cp:
        for r in p: cp.write_row(r)
    t.execute("CREATE INDEX store_pnu ON store (pnu)"); t.execute("ANALYZE cpt"); t.execute("ANALYZE complex_pnu")
    print(f"표본 단지 {len(s)} · 필지 {len(p)}", flush=True)

PG = {
 "poi": """SELECT inds_scls_nm, inds_lcls_nm, sum((d<=300)::int), sum((d<=500)::int), count(*), min(trunc(d)::int), sum(on_site) FROM v WHERE inds_scls_nm IS NOT NULL GROUP BY 1,2""",
 "poiSum": """SELECT count(DISTINCT CASE WHEN d<=500 THEN inds_mcls_cd END), count(DISTINCT inds_mcls_cd), sum(on_site) FROM v""",
 "poiBrand": """SELECT brand, sum((d<=500)::int), count(*), min(trunc(d)::int) FROM v WHERE brand IS NOT NULL GROUP BY 1""",
 "poiLife": """SELECT life, sum((d<=500)::int), count(*), min(trunc(d)::int) FROM v WHERE life IS NOT NULL GROUP BY 1""",
}
PG_V = """WITH c AS (SELECT g FROM cpt WHERE complex_id = %(id)s),
  v AS MATERIALIZED (SELECT s.*, ST_Distance(s.g, c.g) d,
                CASE WHEN EXISTS (SELECT 1 FROM complex_pnu cp WHERE cp.complex_id = %(id)s AND cp.pnu = s.pnu) THEN 1 ELSE 0 END on_site
           FROM store s, c WHERE ST_DWithin(s.g, c.g, 1000))
  """
MS = {
 "poi": """SELECT v.inds_scls_nm, v.inds_lcls_nm, SUM(CASE WHEN v.dist_m<=300 THEN 1 ELSE 0 END), SUM(CASE WHEN v.dist_m<=500 THEN 1 ELSE 0 END), COUNT(*), MIN(CAST(v.dist_m AS INT)), SUM(v.on_site)
           FROM gold.v_complex_poi v WHERE v.complex_id = %d AND v.inds_scls_nm IS NOT NULL GROUP BY v.inds_scls_nm, v.inds_lcls_nm""",
 "poiSum": """SELECT COUNT(DISTINCT CASE WHEN v.dist_m <= 500 THEN v.inds_mcls_cd END), COUNT(DISTINCT v.inds_mcls_cd), SUM(v.on_site) FROM gold.v_complex_poi v WHERE v.complex_id = %d""",
 "poiBrand": """SELECT v.brand, SUM(CASE WHEN v.dist_m <= 500 THEN 1 ELSE 0 END), COUNT(*), MIN(CAST(v.dist_m AS INT)) FROM gold.v_complex_poi v WHERE v.complex_id = %d AND v.brand IS NOT NULL GROUP BY v.brand""",
 "poiLife": """SELECT v.life, SUM(CASE WHEN v.dist_m <= 500 THEN 1 ELSE 0 END), COUNT(*), MIN(CAST(v.dist_m AS INT)) FROM gold.v_complex_poi v WHERE v.complex_id = %d AND v.life IS NOT NULL GROUP BY v.life""",
}
def 맞춤(rows): return sorted(tuple(None if x is None else (int(x) if isinstance(x, (int, float)) or hasattr(x, 'as_integer_ratio') else str(x)) for x in r) for r in rows)

def bench():
    t = pgc("teomoony_test"); ms = ms_conn(E).cursor()
    t.execute("SELECT setseed(0.27)"); ids = [r[0] for r in t.execute("SELECT complex_id FROM cpt WHERE is_active = 1 ORDER BY random() LIMIT 1000").fetchall()]
    sg = dict(t.execute("SELECT complex_id, sgg FROM cpt WHERE complex_id = ANY(%s)", (ids,)).fetchall())
    random.seed(1); random.shuffle(ids)
    tp, tm, n상가 = [], [], []; 다름 = []; 칸다름 = {}
    for i, cid in enumerate(ids):
        a = time.perf_counter(); out = {}
        with t.cursor() as c:
            for k, q in PG.items(): out[k] = c.execute(PG_V + q, {"id": cid}).fetchall()
            ns = c.execute(PG_V + "SELECT count(*) FROM v", {"id": cid}).fetchone()[0]
        tp.append((time.perf_counter() - a) * 1000); n상가.append(ns)
        a = time.perf_counter(); om = {}
        for k, q in MS.items():
            ms.execute("SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; " + q % cid)
            while ms.description is None and ms.nextset(): pass
            om[k] = ms.fetchall()
        tm.append((time.perf_counter() - a) * 1000)
        for k in PG:
            if 맞춤(out[k]) != 맞춤(om[k]):
                칸다름[k] = 칸다름.get(k, 0) + 1
                if len(다름) < 6: 다름.append((cid, k, len(out[k]), len(om[k]), [r for r in 맞춤(out[k]) if r not in 맞춤(om[k])][:2], [r for r in 맞춤(om[k]) if r not in 맞춤(out[k])][:2]))
        if (i + 1) % 100 == 0: print(f"  {i+1}/{len(ids)} · 시험 중간 {statistics.median(tp):.1f}ms · 적재 중간 {statistics.median(tm):.0f}ms", flush=True)
    def 요약(x): x = sorted(x); return f"중간 {x[len(x)//2]:.1f} · 95% {x[int(len(x)*.95)]:.1f} · 최대 {x[-1]:.1f} ms"
    print("시험DB(정규화 · PostGIS) 4질의 합:", 요약(tp))
    print("적재DB(지금 경로)       4질의 합:", 요약(tm))
    seoul = [p for p, cid in zip(tp, ids) if sg[cid].startswith('11')]; rest = [p for p, cid in zip(tp, ids) if not sg[cid].startswith('11')]
    print("  시험DB 서울:", 요약(seoul), "· 서울 밖:", 요약(rest))
    print(f"  1km 안 상가 수: 중간 {statistics.median(n상가):.0f} · 최대 {max(n상가)}")
    print("결과 대조: 다른 단지 수", 칸다름 or "없음 — 전부 같음")
    for d in 다름: print("   ", d)

if __name__ == "__main__":
    {"setup": setup, "bench": bench}[sys.argv[1]]()
