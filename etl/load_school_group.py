#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""load_school_group — 중학교 학교군 · 고등학교 학교군 경계 + 학교학구도연계정보 적재   2026-10-24

  py load_school_group.py

출처(한국교육시설안전원 · data.go.kr · 이용허락 제한 없음 · 기준일 2026-09-20 · 매년 3월·9월 배포)
  15159264 중학교학교군 SHP  → data/hakgudo_mid_4326.ndjson
  15159263 고등학교학교군 SHP → data/hakgudo_high_4326.ndjson
  15159266 학교학구도연계정보 CSV(cp949) → data/hakgudo_link_20260920.csv
  받는 법 · 변환은 data/README.txt (초등 통학구역과 같다 — shp2ndjson.py)

★ 연계정보의 학교ID(B…)는 silver.school(전국초중등학교위치표준데이터)과 **같은 코드**다 — 이름으로 잇지 않는다.
★ 연계정보의 학구ID 는 초등 통학구역(silver.school_zone) · 중학교군 · 고교 학군 셋 다를 가리킨다.
"""
import csv, io, json, os, sys, time
import pymssql

from load_building import load_env
from load_school_zone import to_wkt

HERE = os.path.dirname(os.path.abspath(__file__))
ENV  = os.path.join(HERE, "..", ".env")
DATA = os.path.join(HERE, "data")
SRC  = [("M", os.path.join(DATA, "hakgudo_mid_4326.ndjson")), ("H", os.path.join(DATA, "hakgudo_high_4326.ndjson"))]
LINK = os.path.join(DATA, "hakgudo_link_20260920.csv")


def main():
    for _, p in SRC + [("L", LINK)]:
        if not os.path.isfile(p): sys.exit(f"없는 파일: {p} (data/README.txt)")
    env = load_env(ENV)
    conn = pymssql.connect(server=env.get("DB_HOST", "127.0.0.1"), port=int(env.get("DB_PORT", 11433)),
                           user=env.get("DB_USER", "sa"), password=env.get("DB_PASSWORD", ""),
                           database=env.get("DB_NAME", "Teomoony"), charset="UTF-8", autocommit=False)
    cur = conn.cursor()
    today = time.strftime("%Y%m%d")
    for kind, p in SRC:
        n = bad = 0
        with io.open(p, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line: continue
                d = json.loads(line)
                try: wkt = to_wkt(d["geom"])
                except Exception as e:
                    bad += 1; print(f"  건너뜀 {d.get('id')} — {e}"); continue
                cur.execute("DELETE FROM silver.school_group WHERE kind = %s AND hakgudo_id = %s", (kind, d["id"]))
                cur.execute("""INSERT INTO silver.school_group
                       (kind, hakgudo_id, hakgudo_nm, hakgudo_gb, sd_cd, sgg_cd, edu_nm, base_dt, geom,
                        bbox_minx, bbox_miny, bbox_maxx, bbox_maxy, collected_at)
                       SELECT %s,%s,%s,%s,%s,%s,%s,%s, g,
                              g.STEnvelope().STPointN(1).STX, g.STEnvelope().STPointN(1).STY,
                              g.STEnvelope().STPointN(3).STX, g.STEnvelope().STPointN(3).STY, %s
                         FROM (SELECT geometry::STGeomFromText(%s, 4326).MakeValid() AS g) t""",
                    (kind, d["id"], d.get("nm"), d.get("gb"), d.get("sd"), d.get("sgg") or None,
                     d.get("edu"), d.get("base"), today, wkt))
                n += 1
                if n % 200 == 0: conn.commit(); print(f"  {kind} {n:,}", flush=True)
        conn.commit()
        print(f"{'중학교' if kind == 'M' else '고등학교'} 학교군 {n:,} 넣음 · 건너뜀 {bad}", flush=True)

    raw = open(LINK, "rb").read()
    try: txt = raw.decode("utf-8-sig")
    except UnicodeDecodeError: txt = raw.decode("cp949")
    rows = list(csv.DictReader(io.StringIO(txt)))
    need = ["학구ID", "학교ID", "학교명", "학교급구분", "시도교육청코드", "교육지원청코드", "교육지원청명", "데이터기준일자"]
    miss = [k for k in need if k not in (rows[0] if rows else {})]
    if miss: sys.exit(f"연계정보 칸이 바뀜: 없음 {miss}")
    cur.execute("DELETE FROM silver.school_zone_link")
    for r in rows:
        cur.execute("""INSERT INTO silver.school_zone_link (hakgudo_id, school_id, school_nm, school_lvl, sido_edu_cd, edu_cd, edu_nm, base_dt, collected_at)
                       VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
                    (r["학구ID"], r["학교ID"], r["학교명"], r["학교급구분"], r["시도교육청코드"], r["교육지원청코드"], r["교육지원청명"], r["데이터기준일자"], today))
    conn.commit()
    cur.execute("SELECT COUNT(*) FROM silver.school_zone_link")
    print(f"연계정보 {cur.fetchone()[0]:,}줄 넣음")
    conn.close()


if __name__ == "__main__":
    main()
