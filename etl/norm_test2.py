# -*- coding: utf-8 -*-
"""norm_test2 - 정규화 시험 2단계: 학교 (2026-10-27) — 시험 DB teomoony_test 에만 쓴다.
  원천 표(원본 그대로 · 한 번): school · school_link(위치↔알리미, 335 규칙 결과) · schoolinfo · schoolinfo_stat · school_zone · school_group · school_zone_link(공식 대응표)
  매칭 표: complex_zone(단지 → 통학구역 · 학교군 행) — 단지 가운데 점이 구역 경계 안(적재DB 와 같은 STContains 뜻 = PostGIS ST_Contains, 평면 4326)
  거리(주변 학교 2km): 매칭 표 없이 공간 색인(ST_DWithin).
  적재DB 쪽 질의는 **화면 서버(src/server.js) 의 _q_schoolZone · _q_schools 글자 그대로** 떼어 와 돌린다(따로 적으면 갈라진다).
  py norm_test2.py setup | bench"""
import re, sys, time, random, statistics, decimal, datetime
from svc_publish import env, ms_conn
from norm_test import pgc
E = env()
SRV = r"C:\Project\Teomoony-f\src\server.js"
T = {  # 표 → (적재DB 원천, 공간 칸, 공간 종류)
 "school": ("silver.school", "geog", "geography"), "school_link": ("gold.school_link", None, None),
 "schoolinfo": ("silver.schoolinfo", None, None), "schoolinfo_stat": ("silver.schoolinfo_stat", None, None),
 "school_zone": ("silver.school_zone", "geom", "geometry"), "school_group": ("silver.school_group", "geom", "geometry"),
 "school_zone_link": ("silver.school_zone_link", None, None)}
PGT = {"int": "bigint", "bigint": "bigint", "smallint": "int", "tinyint": "int", "bit": "int", "decimal": "numeric", "numeric": "numeric",
       "float": "float8", "real": "float8", "date": "date", "datetime2": "timestamp", "datetime": "timestamp", "binary": "bytea", "varbinary": "bytea"}

def setup():
    t = pgc("teomoony_test"); ms = ms_conn(E).cursor()
    for name, (src, gc, gk) in T.items():
        sch, tb = src.split(".")
        ms.execute("SELECT COLUMN_NAME, DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA=%s AND TABLE_NAME=%s ORDER BY ORDINAL_POSITION", (sch, tb))
        cols = [(c, ty) for c, ty in ms.fetchall() if c not in ("raw_json",)]
        sel = ", ".join(f"[{c}].STAsBinary()" if c == gc else f"[{c}]" for c, ty in cols)
        t.execute(f"DROP TABLE IF EXISTS {name}")
        t.execute(f"CREATE TABLE {name} (" + ", ".join(f'"{c}" ' + ("bytea" if c == gc else PGT.get(ty, "text")) for c, ty in cols) + ")")
        ms.execute(f"SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; SELECT {sel} FROM {src}")
        while ms.description is None and ms.nextset(): pass
        rows = ms.fetchall()
        with t.cursor() as c, c.copy(f"COPY {name} FROM STDIN") as cp:
            for r in rows: cp.write_row([int(x) if isinstance(x, bool) else x for x in r])
        if gc:
            t.execute(f'ALTER TABLE {name} ADD COLUMN g {gk}')
            t.execute(f'UPDATE {name} SET g = ' + ("ST_GeogFromWKB(\"%s\")" % gc if gk == "geography" else "ST_SetSRID(ST_GeomFromWKB(\"%s\"), 4326)" % gc))
            t.execute(f'CREATE INDEX ON {name} USING gist (g)')
        print(f"  {name}: {len(rows):,}줄", flush=True)
    for ix in ["school_zone_link (hakgudo_id)", "school_link (school_id)", "schoolinfo (schul_code)", "schoolinfo_stat (schul_code, pban_yr DESC)", "school (school_id)", "schoolinfo (left(adrcd_cd, 5))"]:
        t.execute(f"CREATE INDEX ON {ix}")
    # 매칭 표: 표본 단지의 통학구역 · 학교군(행 번호로 — 같은 구역ID 가 여러 행이어도 적재DB 와 같게)
    a = time.time()
    t.execute("DROP TABLE IF EXISTS complex_zone")
    t.execute("""CREATE TABLE complex_zone AS
        SELECT c.complex_id, 'E' kind, z.zone_sk sk FROM cpt c JOIN school_zone z ON ST_Contains(z.g, ST_SetSRID(ST_MakePoint(c.lon, c.lat), 4326))
        UNION ALL
        SELECT c.complex_id, 'G', g.group_sk FROM cpt c JOIN school_group g ON ST_Contains(g.g, ST_SetSRID(ST_MakePoint(c.lon, c.lat), 4326))""")
    t.execute("CREATE INDEX ON complex_zone (complex_id)"); t.execute("ANALYZE")
    n = t.execute("SELECT count(*) FROM complex_zone").fetchone()[0]
    print(f"  complex_zone(매칭): 표본 {n}줄 · {time.time()-a:.1f}초", flush=True)

PG_Z0 = """SELECT z.hakgudo_nm, CASE WHEN z.hakgudo_gb = '1' THEN 1 ELSE 0 END, z.edu_nm, z.base_dt
  FROM complex_zone cz JOIN school_zone z ON z.zone_sk = cz.sk WHERE cz.complex_id = %(id)s AND cz.kind = 'E'"""
ST = """LEFT JOIN LATERAL (SELECT t.stdnt_cnt, t.class_cnt, t.per_class, t.teach_cnt, t.per_teacher, t.pban_yr, t.excp_yn, t.excp_rsn
                     FROM schoolinfo_stat t WHERE t.schul_code = l.schul_code ORDER BY t.pban_yr DESC LIMIT 1) st ON true"""
ALIMI = "CASE WHEN EXISTS (SELECT 1 FROM schoolinfo i2 WHERE left(i2.adrcd_cd, 5) = c.sgg) THEN 1 ELSE 0 END"
PG_Z1 = f"""WITH c AS (SELECT * FROM cpt WHERE complex_id = %(id)s),
 z AS (SELECT '초등학교' 급, '통학구역' 구역종류, z.hakgudo_id 구역id, z.hakgudo_nm 구역, CASE WHEN z.hakgudo_gb = '1' THEN 1 ELSE 0 END 공동
         FROM complex_zone cz JOIN school_zone z ON z.zone_sk = cz.sk WHERE cz.complex_id = %(id)s AND cz.kind = 'E'
       UNION ALL
       SELECT CASE g.kind WHEN 'M' THEN '중학교' ELSE '고등학교' END, CASE g.kind WHEN 'M' THEN '중학교 학교군' ELSE '고등학교 학교군' END,
              g.hakgudo_id, g.hakgudo_nm, CASE WHEN g.hakgudo_gb = '1' THEN 1 ELSE 0 END
         FROM complex_zone cz JOIN school_group g ON g.group_sk = cz.sk WHERE cz.complex_id = %(id)s AND cz.kind = 'G')
SELECT z.급, z.구역종류, z.구역id, z.구역, z.공동, k.base_dt, k.school_id, k.school_nm, s.school_nm, s.fond_type, s.oper_sttus,
       CASE WHEN s.g IS NOT NULL THEN trunc(ST_Distance(s.g, c.g))::int END, CASE WHEN l.schul_code IS NOT NULL THEN 1 ELSE 0 END,
       st.stdnt_cnt, st.class_cnt, st.per_class, st.teach_cnt, st.per_teacher, st.pban_yr, st.excp_yn, st.excp_rsn, {ALIMI}
  FROM z CROSS JOIN c
  LEFT JOIN school_zone_link k ON k.hakgudo_id = z.구역id
  LEFT JOIN school s ON s.school_id = k.school_id AND s.is_current = 1
  LEFT JOIN school_link l ON l.school_id = k.school_id
  {ST}"""
PG_V = """WITH c AS (SELECT * FROM cpt WHERE complex_id = %(id)s),
 v AS MATERIALIZED (SELECT s.*, ST_Distance(s.g, c.g) d FROM school s, c
                     WHERE s.is_current = 1 AND s.g IS NOT NULL AND s.oper_sttus = '운영' AND ST_DWithin(s.g, c.g, 2000)),
 n AS (SELECT school_id, school_se, school_nm, fond_type, bnhh_se, d,
              row_number() OVER (PARTITION BY school_se ORDER BY d) rn,
              sum(CASE WHEN d <= 1000 THEN 1 ELSE 0 END) OVER (PARTITION BY school_se) k1 FROM v)"""
ORD = "CASE {x} WHEN '초등학교' THEN 1 WHEN '중학교' THEN 2 WHEN '고등학교' THEN 3 ELSE 9 END"
PG_S0 = PG_V + f""", a AS (SELECT school_se, sum(CASE WHEN d <= 500 THEN 1 ELSE 0 END) r500, sum(CASE WHEN d <= 1000 THEN 1 ELSE 0 END) r1000, count(*) r2000 FROM v GROUP BY school_se)
SELECT a.school_se, n.school_nm, n.fond_type, n.bnhh_se, trunc(n.d)::int, a.r500, a.r1000, a.r2000, CASE WHEN l.schul_code IS NOT NULL THEN 1 ELSE 0 END,
       st.stdnt_cnt, st.class_cnt, st.per_class, st.teach_cnt, st.per_teacher, st.pban_yr, st.excp_yn, st.excp_rsn, {ALIMI}, {ORD.format(x='a.school_se')}
  FROM a JOIN n ON n.school_se = a.school_se AND n.rn = 1 CROSS JOIN c
  LEFT JOIN school_link l ON l.school_id = n.school_id {ST}"""
PG_S1 = PG_V + f"""
SELECT n.school_id, n.school_se, n.school_nm, n.fond_type, n.bnhh_se, trunc(n.d)::int, CASE WHEN l.schul_code IS NOT NULL THEN 1 ELSE 0 END,
       st.stdnt_cnt, st.class_cnt, st.per_class, st.teach_cnt, st.per_teacher, st.pban_yr, st.excp_yn, st.excp_rsn, i.coedu, i.hmpg, {ALIMI}, {ORD.format(x='n.school_se')}
  FROM n CROSS JOIN c
  LEFT JOIN school_link l ON l.school_id = n.school_id
  LEFT JOIN schoolinfo i ON i.schul_code = l.schul_code {ST}
 WHERE n.d <= 1000 OR (n.k1 = 0 AND n.rn = 1)"""

def 화면질의(name):
    s = open(SRV, encoding="utf-8").read()
    a = s.index(f"const {name} = () => pool.request().input('id', sql.Int, id).query(`") 
    a = s.index("`", a) + 1; b = s.index("`);", a)
    return s[a:b]

def 값(x):
    if x is None: return None
    if isinstance(x, bool): return int(x)
    if isinstance(x, (int,)): return x
    if isinstance(x, (float, decimal.Decimal)): return round(float(x), 4)
    if isinstance(x, (datetime.date, datetime.datetime)): return str(x)
    return str(x).strip()
def 맞춤(rows): return sorted((tuple(값(v) for v in r) for r in rows), key=repr)

def bench():
    t = pgc("teomoony_test"); ms = ms_conn(E).cursor()
    QZ, QS = 화면질의("_q_schoolZone"), 화면질의("_q_schools")
    ids = [r[0] for r in t.execute("SELECT complex_id FROM cpt").fetchall()]
    random.seed(2); random.shuffle(ids)
    tp, tm, 다름, 예 = [], [], {}, []
    for i, cid in enumerate(ids):
        a = time.perf_counter()
        with t.cursor() as c:
            p = [c.execute(q, {"id": cid}).fetchall() for q in (PG_Z0, PG_Z1, PG_S0, PG_S1)]
        tp.append((time.perf_counter() - a) * 1000)
        a = time.perf_counter(); m = []
        for q in (QZ, QS):
            ms.execute(f"DECLARE @id INT = {int(cid)};\n" + q)
            while True:
                if ms.description is not None: m.append(ms.fetchall())
                if not ms.nextset(): break
        tm.append((time.perf_counter() - a) * 1000)
        for k, x, y in zip(("schoolZone", "schoolGroups", "schools", "schoolList"), p, m):
            if 맞춤(x) != 맞춤(y):
                다름[k] = 다름.get(k, 0) + 1
                if len(예) < 6: 예.append((cid, k, len(x), len(y), [r for r in 맞춤(x) if r not in 맞춤(y)][:1], [r for r in 맞춤(y) if r not in 맞춤(x)][:1]))
        if (i + 1) % 100 == 0: print(f"  {i+1}/{len(ids)} · 시험 중간 {statistics.median(tp):.1f}ms · 적재 중간 {statistics.median(tm):.0f}ms", flush=True)
    def 요약(x): x = sorted(x); return f"중간 {x[len(x)//2]:.1f} · 95% {x[int(len(x)*.95)]:.1f} · 최대 {x[-1]:.1f} ms"
    print("시험DB(학교 · 매칭표 + 공간 색인):", 요약(tp)); print("적재DB(지금 화면 질의 그대로):  ", 요약(tm))
    print("결과 대조:", 다름 or "없음 — 전부 같음")
    for e in 예: print("   ", e)

if __name__ == "__main__":
    {"setup": setup, "bench": bench}[sys.argv[1]]()
