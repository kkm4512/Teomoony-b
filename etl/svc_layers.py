#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""svc_layers - 지도 층(필지 · 건물 · 법정동 · 행정동 · 닫힌 대장 핀 · 신축 핀)을 서비스DB 로 (2026-10-25, 2단계)
  py svc_layers.py            # 바뀐 층만(원천 지문이 같으면 건너뜀) — 매시 발행이 부른다
  py svc_layers.py --force parcel,building
★ 각 층 = 적재DB 의 '지금 화면 질의' 에서 bbox 조건만 뺀 것 그대로 + bbox 칸. 새 표(_new)를 다 채운 뒤 이름을 바꿔 끼운다
  (읽는 쪽은 옛 표 아니면 새 표만 본다 — 반쯤 찬 표를 보지 않는다).
★ 형(型)은 화면 응답과 같게: decimal → float8(node-mssql 이 숫자로 냄) · bigint → text(node-mssql 이 문자열로 냄) · bit → boolean.
★ 원천이 그대로면(지문 같음) 다시 만들지 않는다 — 필지 96만 · 건물 65만은 적재가 있을 때만."""
import argparse, json, sys, time
from decimal import Decimal
from svc_publish import env, ms_conn, pg_conn

D = "double precision"
# 층: (이름, 지문 SQL(없으면 매시), 적재DB 질의, PG 칸 [(이름, 형)], 색인)
LAYERS = [
  ("parcel",
   """SELECT CONCAT((SELECT CONCAT(COUNT_BIG(*), '/', MAX(valid_from), '/', MAX(valid_to)) FROM silver.cadastral_parcel), '|',
                    (SELECT CONCAT(COUNT_BIG(*), '/', CHECKSUM_AGG(CHECKSUM(pnu, complex_id))) FROM gold.complex_pnu), '|',
                    (SELECT CONCAT(COUNT_BIG(*), '/', CHECKSUM_AGG(CHECKSUM(complex_id, complex_nm, dong_cnt, has_recap))) FROM gold.complex))""",
   """SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
      SELECT p.pnu, p.jibun, p.addr, p.jiga, p.geojson, cp.complex_id, c.complex_nm, c.dong_cnt, c.has_recap,
             p.bbox_minx, p.bbox_miny, p.bbox_maxx, p.bbox_maxy
        FROM silver.cadastral_parcel p
        LEFT JOIN gold.complex_pnu cp ON cp.pnu = p.pnu
        LEFT JOIN gold.complex c      ON c.complex_id = cp.complex_id
       WHERE p.is_current = 1""",
   [("pnu", "text"), ("jibun", "text"), ("addr", "text"), ("jiga", D), ("geojson", "text"), ("complex_id", "int"), ("complex_nm", "text"),
    ("dong_cnt", "int"), ("has_recap", "boolean"), ("minx", D), ("miny", D), ("maxx", D), ("maxy", D)],
   ["USING gist (box(point(minx, miny), point(maxx, maxy)))"]),
  ("building",
   """SELECT CONCAT((SELECT CONCAT(COUNT_BIG(*), '/', MAX(valid_from), '/', MAX(valid_to)) FROM silver.building_footprint), '|',
                    (SELECT CONCAT(COUNT_BIG(*), '/', CHECKSUM_AGG(CHECKSUM(pnu, complex_id))) FROM gold.complex_pnu), '|',
                    (SELECT CONCAT(COUNT_BIG(*), '/', CHECKSUM_AGG(CHECKSUM(complex_id, complex_nm, has_recap))) FROM gold.complex))""",
   """SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
      SELECT f.bd_mgt_sn, f.buld_nm, f.buld_no, f.rd_nm, f.gro_flo_co, f.area_m2_approx, f.pnu, f.geojson,
             cp.complex_id, c.complex_nm, c.has_recap,
             f.bbox_minx, f.bbox_miny, f.bbox_maxx, f.bbox_maxy
        FROM silver.building_footprint f
        LEFT JOIN gold.complex_pnu cp ON cp.pnu = f.pnu
        LEFT JOIN gold.complex c      ON c.complex_id = cp.complex_id
       WHERE f.is_current = 1""",
   [("bd_mgt_sn", "text"), ("buld_nm", "text"), ("buld_no", "text"), ("rd_nm", "text"), ("gro_flo_co", "int"), ("area_m2_approx", D),
    ("pnu", "text"), ("geojson", "text"), ("complex_id", "int"), ("complex_nm", "text"), ("has_recap", "boolean"),
    ("minx", D), ("miny", D), ("maxx", D), ("maxy", D)],
   ["USING gist (box(point(minx, miny), point(maxx, maxy)))"]),
  ("lawd_geo",
   "SELECT CONCAT(COUNT_BIG(*), '/', MAX(valid_from), '/', MAX(valid_to)) FROM silver.lawd_boundary",
   "SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; SELECT lawd_cd, geojson FROM silver.lawd_boundary WHERE is_current = 1",
   [("lawd_cd", "text PRIMARY KEY"), ("geojson", "text")], []),
  ("lawd_stat", None,
   """SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
      SELECT lawd_cd, emd_nm, full_nm, centroid_lat, centroid_lng, complex_cnt, dong_cnt, hhld_cnt,
             max_amount, max_area, max_ymd, trade_cnt, bbox_minx, bbox_miny, bbox_maxx, bbox_maxy
        FROM gold.v_lawd_map""",
   [("lawd_cd", "text"), ("emd_nm", "text"), ("full_nm", "text"), ("centroid_lat", D), ("centroid_lng", D), ("complex_cnt", "int"),
    ("dong_cnt", "int"), ("hhld_cnt", "int"), ("max_amount", "text"), ("max_area", "int"), ("max_ymd", "text"), ("trade_cnt", "int"),
    ("minx", D), ("miny", D), ("maxx", D), ("maxy", D)],
   ["USING gist (box(point(minx, miny), point(maxx, maxy)))"]),
  ("adm", None,
   """SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
      SELECT a.adm_cd_sgis, a.year, a.adm_nm, a.emd_nm, a.centroid_lat, a.centroid_lng,
             a.adm_cd_mois, a.mois_nm, a.상가수, a.연결상가, a.연결비율, a.갈림내역, a.geojson,
             연결 = CASE WHEN a.연결비율 >= 90 THEN N'확인' WHEN a.연결비율 IS NOT NULL THEN N'갈림' END,
             a.bbox_minx, a.bbox_miny, a.bbox_maxx, a.bbox_maxy
        FROM silver.adm_boundary a
       WHERE a.year = (SELECT MAX(year) FROM silver.adm_boundary)""",
   [("adm_cd_sgis", "text"), ("year", "text"), ("adm_nm", "text"), ("emd_nm", "text"), ("centroid_lat", D), ("centroid_lng", D),
    ("adm_cd_mois", "text"), ("mois_nm", "text"), ("상가수", "int"), ("연결상가", "int"), ("연결비율", D), ("갈림내역", "text"),
    ("geojson", "text"), ("연결", "text"), ("minx", D), ("miny", D), ("maxx", D), ("maxy", D)], []),
  ("closed", None,
   """SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
      SELECT s.site_key, s.pnu, s.shter_day, s.이름, s.이름출처, s.주용도, s.동수, s.총괄세대, s.사용승인일, s.폐쇄구분,
             s.plat_plc, s.new_plat_plc, s.lat, s.lng, s.now_complex_id, now_nm = c.complex_nm, s.위치근거
        FROM gold.closed_site s LEFT JOIN gold.complex c ON c.complex_id = s.now_complex_id
       WHERE s.lat IS NOT NULL AND s.lng IS NOT NULL""",
   [("site_key", "text"), ("pnu", "text"), ("shter_day", "text"), ("이름", "text"), ("이름출처", "text"), ("주용도", "text"), ("동수", "int"),
    ("총괄세대", "int"), ("사용승인일", "text"), ("폐쇄구분", "text"), ("plat_plc", "text"), ("new_plat_plc", "text"), ("lat", D), ("lng", D),
    ("now_complex_id", "int"), ("now_nm", "text"), ("위치근거", "text")],
   ["(lng, lat)"]),
  ("newbuild", None,
   """SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
      SELECT kapt_code, kapt_name, lawd_nm, pnu, 세대, 동수, 사용승인, 거래, 최고가, centroid_lat, centroid_lng
        FROM gold.v_newbuild WHERE centroid_lat IS NOT NULL""",
   [("kapt_code", "text"), ("kapt_name", "text"), ("lawd_nm", "text"), ("pnu", "text"), ("세대", "int"), ("동수", "int"), ("사용승인", "text"),
    ("거래", "int"), ("최고가", "text"), ("centroid_lat", D), ("centroid_lng", D)], []),
]


from svc_suggest_src import SUGG
LAYERS += SUGG   # 자동완성 원천(sg_*) — 같은 방식(새 표 → 바꿔 끼움 · 큰 표는 지문)


def 값(v, 형):
    if v is None: return None
    if isinstance(v, Decimal): return float(v)
    if 형 == "text" and not isinstance(v, str): return str(v)   # bigint → 문자열(node-mssql 과 같게)
    return v


def build(ms, pg, name, src_sql, cols, idx, post=()):
    t = time.time()
    tb = f"svc.lyr_{name}"
    cur = ms.cursor(); cur.execute(src_sql)
    while cur.description is None and cur.nextset(): pass
    형들 = [c[1].split()[0] for c in cols]
    n = 0
    with pg.cursor() as c:
        c.execute(f"DROP TABLE IF EXISTS {tb}_new")
        c.execute(f"CREATE TABLE {tb}_new (" + ", ".join(f'"{k}" {v}' for k, v in cols) + ")")
        k = len(cur.description)   # 원천 칸 수(뒤의 덧칸은 post 가 채운다)
        with c.copy(f"COPY {tb}_new (" + ", ".join(f'"{x[0]}"' for x in cols[:k]) + ") FROM STDIN") as cp:
            while True:
                rows = cur.fetchmany(5000)
                if not rows: break
                for r in rows:
                    cp.write_row([값(v, 형들[i]) for i, v in enumerate(r)])
                n += len(rows)
        for x in post:   # 채운 뒤 덧칸(예: 너비 무시 비교 키) — {t} = 새 표
            c.execute(x.format(t=f"{tb}_new"))
        for i, ix in enumerate(idx):
            c.execute(f"CREATE INDEX ix_lyr_{name}_new_{i} ON {tb}_new {ix}")
        c.execute(f"ANALYZE {tb}_new")
    pg.commit()
    # 바꿔 끼우기는 짧은 트랜잭션 + 잠금 3초 제한 — 누가 옛 표를 오래 쥐고 있으면(점검 스크립트 등) 기다리지 않고 물러났다 다시.
    # (기다리면 그 뒤로 화면 읽기가 전부 줄을 선다 — 10-25 02:05 sg_sgg 290초)
    import psycopg.errors
    for 번 in range(20):
        try:
            with pg.cursor() as c:
                c.execute("SET LOCAL lock_timeout = '3s'")
                c.execute(f"DROP TABLE IF EXISTS {tb}")
                c.execute(f"ALTER TABLE {tb}_new RENAME TO lyr_{name}")
                for i, _ in enumerate(idx):
                    c.execute(f"ALTER INDEX svc.ix_lyr_{name}_new_{i} RENAME TO ix_lyr_{name}_{i}")
            pg.commit(); break
        except psycopg.errors.LockNotAvailable:
            pg.rollback(); time.sleep(5)
    else:
        raise RuntimeError(f"{tb}: 바꿔 끼우기 잠금을 못 잡음(100초)")
    return n, time.time() - t


def run(ms, pg, force=(), only=()):
    with pg.cursor() as c:
        c.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")
        # 이름 정렬: 적재DB(Korean_Wansung_CI_AS) 와 비슷하게 — 한글은 음절 순, 영문은 대소문자 구분 없이(level2)
        c.execute("SELECT 1 FROM pg_collation WHERE collname = 'ko_ci' AND collnamespace = 'svc'::regnamespace")
        if not c.fetchone(): c.execute("CREATE COLLATION svc.ko_ci (provider = icu, locale = 'ko-KR-u-ks-level2', deterministic = false)")
        c.execute("""CREATE TABLE IF NOT EXISTS svc.layer_state (layer text PRIMARY KEY, fingerprint text, rows int,
                      built_at timestamptz, secs real)""")
        c.execute("SELECT layer, fingerprint FROM svc.layer_state"); 전 = dict(c.fetchall())
    pg.commit()
    for spec in LAYERS:
        name, fp_sql, src, cols, idx = spec[:5]; post = spec[5] if len(spec) > 5 else ()
        if only and name not in only and not any(o.endswith('*') and name.startswith(o[:-1]) for o in only): continue
        fp = None
        if fp_sql:
            cur = ms.cursor(); cur.execute(fp_sql); fp = str(cur.fetchone()[0])
            if fp == 전.get(name) and name not in force:
                print(f"  층 {name}: 원천 그대로 — 건너뜀", flush=True); continue
        n, s = build(ms, pg, name, src, cols, idx, post)
        with pg.cursor() as c:
            c.execute("""INSERT INTO svc.layer_state VALUES (%s, %s, %s, now(), %s)
                         ON CONFLICT (layer) DO UPDATE SET fingerprint = EXCLUDED.fingerprint, rows = EXCLUDED.rows,
                                                           built_at = EXCLUDED.built_at, secs = EXCLUDED.secs""", (name, fp, n, s))
        pg.commit()
        print(f"  층 {name}: {n:,}줄 · {s:.0f}초", flush=True)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", default=""); ap.add_argument("--only", default="")
    a = ap.parse_args()
    e = env(); ms = ms_conn(e); pg = pg_conn(e)
    t = time.time()
    run(ms, pg, set(filter(None, a.force.split(","))), set(filter(None, a.only.split(","))))
    print(f"지도 층 끝 · {time.time() - t:.0f}초")
