#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""load_vworld_zone - VWorld 용도지역·지구·구역 경계를 silver.vworld_zone 에 적재 (2026-10-22, deploy/sql/304)

  py load_vworld_zone.py                          적재 대상 시군구 전부 · 레이어 전부
  py load_vworld_zone.py --sgg 11290 --layer LT_C_UQ141

★ 시군구 경계상자(필지 bbox)를 8km2 조각(split_box)으로 썰어 받는다. 조각 하나라도 실패하면 그 시군구·레이어는 '다 받음' 으로 안 적는다.
★ 자연키 = 레이어 + 속성 + 좌표 sha256. 이미 있으면 마지막본시각만 갱신. 못 본 것은 닫지 않는다(--close-stale 없음 — 필요하면 따로).
★ VWorld 키는 화면·로그에 안 찍는다. 도메인은 .env VWORLD_DOMAIN.
"""
import argparse, hashlib, json, os, sys, time
import requests
import pymssql
from load_building import load_env, split_box, stats, wkt

HERE = os.path.dirname(os.path.abspath(__file__))
ENV = os.path.join(HERE, "..", ".env")
VW = "https://api.vworld.kr/req/data"
LAYERS = ["LT_C_UQ141", "LT_C_UQ111", "LT_C_UQ121", "LT_C_UQ123", "LT_C_UQ124", "LT_C_UQ128", "LT_C_UQ129",
          "LT_C_UQ162", "LT_C_UO101", "LT_C_LHZONE"]


def fetch_box(key, dom, layer, box, retries=4):
    """조각 하나를 페이지 끝까지. 실패하면 None (빈 것과 다르다)."""
    feats, page = [], 1
    while True:
        p = {"service": "data", "version": "2.0", "request": "GetFeature", "key": key, "data": layer, "geomFilter": box,
             "geometry": "true", "attribute": "true", "crs": "EPSG:4326", "format": "json", "size": "1000",
             "page": str(page), "domain": dom}
        last = None
        for a in range(retries):
            try:
                r = requests.get(VW, params=p, timeout=120)
                try:
                    j = r.json().get("response", {})
                except ValueError:
                    j = {"status": "BROKEN_JSON"}
                last = j
                if j.get("status") == "OK": break
                if j.get("status") == "NOT_FOUND": return feats
            except Exception as e:
                last = {"status": "EXCEPTION", "error": type(e).__name__}
            time.sleep(2 * (a + 1))
        if not last or last.get("status") != "OK":
            print(f"    ! {layer} {box} p{page}: {str(last.get('status') if last else '?')}", flush=True)
            return None
        feats += last["result"]["featureCollection"]["features"]
        if page >= int(last.get("page", {}).get("total", 1)): break
        page += 1; time.sleep(0.15)
    return feats


def 이름(pr):
    return pr.get("uname") or pr.get("dgm_nm") or pr.get("zonename") or None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sgg", nargs="*"); ap.add_argument("--layer", nargs="*"); ap.add_argument("--pad", type=float, default=0.0008)
    ap.add_argument("--skip-done", action="store_true", help="이미 다 받은 시군구·레이어는 건너뛴다")
    a = ap.parse_args()
    env = load_env(ENV)
    key = env.get("VWORLD_KEY", "").strip(); dom = (env.get("VWORLD_DOMAIN") or "teomoony.com").strip()
    if not key: sys.exit(".env 의 VWORLD_KEY 가 비어 있습니다")
    conn = pymssql.connect(server=env.get("DB_HOST", "127.0.0.1"), port=int(env.get("DB_PORT", 11433)), user=env.get("DB_USER", "sa"),
                           password=env.get("DB_PASSWORD", ""), database=env.get("DB_NAME", "Teomoony"), charset="UTF-8", autocommit=False)
    cur = conn.cursor()
    cur.execute("""SELECT LEFT(pnu,5), MIN(bbox_minx), MIN(bbox_miny), MAX(bbox_maxx), MAX(bbox_maxy)
                     FROM silver.cadastral_parcel WHERE is_current = 1
                      AND LEFT(pnu,5) IN (SELECT sgg_cd FROM meta.v_target_sgg)   -- 2026-10-24: 이웃 시군구에 넘쳐 받은 필지 말고 적재 대상만
                    GROUP BY LEFT(pnu,5) ORDER BY 1""")
    sggs = cur.fetchall()
    if a.sgg: sggs = [x for x in sggs if x[0] in set(a.sgg)]
    layers = a.layer or LAYERS
    done = set()
    if a.skip_done:
        cur.execute("SELECT layer, sgg_cd FROM silver.vworld_zone_done WHERE 빈조각 = 0"); done = {(r[0], r[1].strip()) for r in cur.fetchall()}
    print(f"시군구 {len(sggs)} × 레이어 {len(layers)}", flush=True)
    t0 = time.monotonic(); 합신규 = 0
    for layer in layers:
        for sgg, x0, y0, x1, y1 in sggs:
            if (layer, sgg) in done: continue
            tiles = split_box(float(x0) - a.pad, float(y0) - a.pad, float(x1) + a.pad, float(y1) + a.pad)
            seen, 신규, 수신, 빈 = set(), 0, 0, 0
            for (tx0, ty0, tx1, ty1) in tiles:
                fs = fetch_box(key, dom, layer, f"BOX({tx0},{ty0},{tx1},{ty1})")
                if fs is None: 빈 += 1; continue
                수신 += len(fs)
                for f in fs:
                    pr = f.get("properties") or {}; g = f.get("geometry") or {}
                    if g.get("type") not in ("MultiPolygon", "Polygon"): continue
                    co = g["coordinates"] if g["type"] == "MultiPolygon" else [g["coordinates"]]
                    w = wkt(co)
                    attrs = json.dumps(pr, ensure_ascii=False, sort_keys=True)
                    zk = hashlib.sha256((layer + "\x1f" + attrs + "\x1f" + w).encode("utf-8")).hexdigest()
                    if zk in seen: continue
                    seen.add(zk)
                    minx, miny, maxx, maxy = stats(co)
                    cur.execute("UPDATE silver.vworld_zone SET 마지막본시각 = SYSDATETIME(), is_current = 1 WHERE layer = %s AND zone_key = %s", (layer, zk))
                    if cur.rowcount == 0:
                        cur.execute("""INSERT INTO silver.vworld_zone (layer, zone_key, 이름, dyear, dnum, sido_name, sigg_name, attrs_json, geojson, geom,
                                                                       bbox_minx, bbox_miny, bbox_maxx, bbox_maxy)
                                       VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s, geometry::STGeomFromText(%s, 4326).MakeValid(), %s,%s,%s,%s)""",
                                    (layer, zk, 이름(pr), pr.get("dyear") or None, pr.get("dnum") or None, pr.get("sido_name") or None,
                                     pr.get("sigg_name") or None, attrs[:2000],
                                     json.dumps({"type": "MultiPolygon", "coordinates": co}, separators=(",", ":")), w,
                                     round(minx, 7), round(miny, 7), round(maxx, 7), round(maxy, 7)))
                        신규 += 1
                conn.commit()
                time.sleep(0.1)
            cur.execute("""MERGE silver.vworld_zone_done AS t USING (SELECT %s AS layer, %s AS sgg_cd) s ON t.layer = s.layer AND t.sgg_cd = s.sgg_cd
                           WHEN MATCHED THEN UPDATE SET 수신 = %s, 빈조각 = %s, 받은시각 = SYSDATETIME()
                           WHEN NOT MATCHED THEN INSERT (layer, sgg_cd, 수신, 빈조각) VALUES (%s, %s, %s, %s);""",
                        (layer, sgg, 수신, 빈, layer, sgg, 수신, 빈))
            conn.commit(); 합신규 += 신규
            print(f"  {layer} {sgg} 조각 {len(tiles)} · 수신 {수신:,} · 신규 {신규:,}" + (f" · ★ 실패 조각 {빈}" if 빈 else "")
                  + f"  ({(time.monotonic() - t0) / 60:.1f}분)", flush=True)
    cur.execute("SELECT layer, COUNT(*) FROM silver.vworld_zone WHERE is_current = 1 GROUP BY layer ORDER BY layer")
    print("\n레이어별:", ", ".join(f"{l} {n:,}" for l, n in cur.fetchall()))
    cur.execute("SELECT COUNT(*) FROM silver.vworld_zone_done WHERE 빈조각 > 0")
    print(f"신규 {합신규:,} · 실패 조각이 있는 시군구·레이어 {cur.fetchone()[0]} (다시: --skip-done)")
    conn.close()


if __name__ == "__main__":
    main()
