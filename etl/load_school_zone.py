#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
load_school_zone - 초등학교 통학구역(학구도) 폴리곤을 silver.school_zone 에 적재

  py load_school_zone.py

출처: 한국교육시설안전원_초등학교통학구역 (data.go.kr 15159265)
      SHP · 전국 7,132개 · **이용허락범위 제한 없음** · 기준일 2026-09-20
      `silver.school` 과 같은 기관이다. 7종이 매년 3월·9월 배포된다.

★ 원본은 SHP(EPSG:5186) 라 **받을 때 한 번 4326 ndjson 으로 바꿔서** 넣는다.
  (정비구역 uq120 과 같은 방식. 변환법은 data/README.txt)
  윈도우 쪽 파이썬에 pyshp/pyproj 를 깔지 않으려는 이유도 같다 -
  파이프라인에 의존을 늘리는 것보다 받을 때 한 번 바꾸는 게 싸다.

★ 왜 필요한가: 거리로 학군을 말하면 그럴듯하게 틀린다.
  '가장 가까운 초등학교' 와 '배정되는 초등학교' 는 다른 말이다.
"""
import io, json, os, sys, time
import pymssql

from load_building import load_env

HERE = os.path.dirname(os.path.abspath(__file__))
ENV  = os.path.join(HERE, "..", ".env")
SRC  = os.path.join(HERE, "data", "hakgudo_elem_4326.ndjson")


def _notify(title, lines):
    try:
        import notify
        ok, why = notify.send("[터무니] " + title + "\n" + "\n".join(lines))
        print(f"[알림] {'보냄' if ok else '안 보냄 - ' + str(why)}")
    except Exception as e:
        print(f"[알림] 실패 - {type(e).__name__}: {e}")


def ring_wkt(ring):
    pts = ", ".join(f"{x} {y}" for x, y in ring)
    return f"({pts})"


def to_wkt(g):
    """Polygon / MultiPolygon -> WKT. 링 방향은 손대지 않는다 -
       SQL Server geometry 는 방향을 따지지 않는다(geography 와 다르다)."""
    t = g["type"]
    if t == "Polygon":
        return "POLYGON (" + ", ".join(ring_wkt(r) for r in g["coordinates"]) + ")"
    if t == "MultiPolygon":
        parts = []
        for poly in g["coordinates"]:
            parts.append("(" + ", ".join(ring_wkt(r) for r in poly) + ")")
        return "MULTIPOLYGON (" + ", ".join(parts) + ")"
    raise ValueError("모르는 도형: " + t)


def main():
    if not os.path.isfile(SRC):
        sys.exit(f"없는 파일: {SRC} (받는 법은 data/README.txt)")
    env = load_env(ENV)
    conn = pymssql.connect(server=env.get("DB_HOST", "127.0.0.1"),
                           port=int(env.get("DB_PORT", 11433)),
                           user=env.get("DB_USER", "sa"),
                           password=env.get("DB_PASSWORD", ""),
                           database=env.get("DB_NAME", "Teomoony"),
                           charset="UTF-8", autocommit=False)
    cur = conn.cursor()
    today = time.strftime("%Y%m%d")
    n = bad = 0
    gb = {}
    with io.open(SRC, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            d = json.loads(line)
            try:
                wkt = to_wkt(d["geom"])
            except Exception as e:
                bad += 1
                print(f"  건너뜀 {d.get('id')} — {e}")
                continue
            gb[d.get("gb")] = gb.get(d.get("gb"), 0) + 1
            cur.execute("DELETE FROM silver.school_zone WHERE hakgudo_id = %s", (d["id"],))
            cur.execute("""INSERT INTO silver.school_zone
                   (hakgudo_id, hakgudo_nm, hakgudo_gb, sd_cd, sgg_cd, edu_nm,
                    base_dt, geom, bbox_minx, bbox_miny, bbox_maxx, bbox_maxy, collected_at)
                   SELECT %s,%s,%s,%s,%s,%s,%s, g,
                          g.STEnvelope().STPointN(1).STX, g.STEnvelope().STPointN(1).STY,
                          g.STEnvelope().STPointN(3).STX, g.STEnvelope().STPointN(3).STY, %s
                     FROM (SELECT geometry::STGeomFromText(%s, 4326).MakeValid() AS g) t""",
                (d["id"], d.get("nm"), d.get("gb"), d.get("sd"), d.get("sgg"),
                 d.get("edu"), d.get("base"), today, wkt))
            n += 1
    conn.commit()
    cur.execute("SELECT COUNT(*) FROM silver.school_zone")
    tot = cur.fetchone()[0]
    print(f"\n학구 {n:,}건 넣음 (총 {tot:,}) · 건너뜀 {bad}")
    print(f"  구분: " + " · ".join(f"{k}={v}" for k, v in sorted(gb.items()))
          + "   (0 단독 / 1 공동통학구역)")
    _notify("학구도 적재 완료", [f"초등 통학구역 {tot:,}건"])
    conn.close()


if __name__ == "__main__":
    main()
