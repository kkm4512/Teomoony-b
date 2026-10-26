#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
load_ri_geom - VWorld **리** 경계(LT_C_ADRI_INFO)를 silver.ri_boundary 에 적재 (2026-10-26 · load_lawd_geom 에서 갈라 냄)
  py load_ri_geom.py --all       # 전국 (리가 있는 시군구만 받는다 — 동만 있는 구는 VWorld 가 NOT_FOUND)

  py load_lawd_geom.py --sgg 11110            # 종로구 87개 법정동
  py load_lawd_geom.py --sgg 11110 11290      # 여러 시군구
  py load_lawd_geom.py --sgg 11290 --lawd 1129013800   # 장위동만

동작
  1) 시군구 단위로 VWorld 를 호출한다 (emd_cd:like:<시군구코드5>)
     - 법정동을 하나씩 부르지 않는다. 시군구 1회(페이징)로 끝난다.
  2) silver.ri_boundary 에 SCD2 로 적재

주의
  * emd_cd 는 8자리다. 우리 법정동코드는 10자리이고 뒤에 리코드 '00' 이 붙는다.
      lawd_cd = emd_cd + '00'     (11110118 -> 1111011800 내수동)
    종로구로 확인: 87개로 meta.lawd_code 와 수가 맞는다.
  * crs=EPSG:4326 으로 받는다. 좌표 변환이 필요 없다.
  * 중심좌표는 bbox 중앙이다. 오목한 동이면 경계 밖으로 나갈 수 있는데,
    마커 위치로만 쓰므로 그대로 둔다. 정확한 무게중심이 필요해지면
    geom.STCentroid() 로 DB 에서 다시 계산할 것.
"""
import argparse, hashlib, json, os, sys, time
import requests
import pymssql

HERE  = os.path.dirname(os.path.abspath(__file__))
ENV   = os.path.join(HERE, "..", ".env")
VW    = "https://api.vworld.kr/req/data"
LAYER = "LT_C_ADRI_INFO"



# ★ VWorld 키는 **등록 도메인에 묶인다** (2026-10-20 실측).
#   domain=localhost -> INCORRECT_KEY. 그런데 fetch 가 그 단위만 건너뛰고 넘어가서
#   **적재가 조용히 0건이 된다.** 실제로 필지가 446,040 에서 멈췄는데 끝까지 돌면
#   "OK" 로 보고될 뻔했다. 하드코딩하지 않고 .env 의 VWORLD_DOMAIN 을 읽는다.
def vworld_domain(env):
    return (env.get("VWORLD_DOMAIN") or "teomoony.com").strip()


DOMAIN = "teomoony.com"   # main() 에서 .env 값으로 덮어쓴다


def load_env(path):
    d = {}
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                d[k.strip()] = v.strip()
    return d


def fetch_sgg(key, sgg, retries=3):
    """시군구 하나의 법정동 경계를 전부 가져온다 (페이지당 1000)."""
    feats, page = [], 1
    while True:
        p = {"service": "data", "version": "2.0", "request": "GetFeature",
             "key": key, "data": LAYER, "attrFilter": f"li_cd:like:{sgg}",
             "geometry": "true", "attribute": "true", "crs": "EPSG:4326",
             "format": "json", "size": "1000", "page": str(page),
             "domain": DOMAIN}
        last = None
        for a in range(retries):
            try:
                j = requests.get(VW, params=p, timeout=120).json().get("response", {})
                last = j
                if j.get("status") == "OK":
                    break
                if j.get("status") == "NOT_FOUND":
                    return feats
            except Exception as e:
                last = {"status": "EXCEPTION", "error": str(e)}
            time.sleep(1.5 * (a + 1))
        if not last or last.get("status") != "OK":
            print(f"    ! {sgg} page {page}: {json.dumps(last, ensure_ascii=False)[:160]}")
            # ★ 2026-10-21: 받은 데까지만 넣고 '완료' 로 끝나면 안 된다(작업방식: 못 읽음 ≠ 0). 실패를 위로 올린다.
            raise RuntimeError(f"{sgg} page {page} 실패")
        feats += last["result"]["featureCollection"]["features"]
        total = int(last.get("page", {}).get("total", 1))
        if page >= total:
            break
        page += 1
        time.sleep(0.15)
    return feats


def ring_stats(coords):
    xs, ys = [], []
    stack = [coords]
    while stack:
        c = stack.pop()
        if isinstance(c[0], (int, float)):
            xs.append(c[0]); ys.append(c[1])
        else:
            stack.extend(c)
    return min(xs), min(ys), max(xs), max(ys)


def wkt(mp):
    polys = []
    for poly in mp:
        rings = []
        for ring in poly:
            rings.append("(" + ", ".join(f"{x} {y}" for x, y in ring) + ")")
        polys.append("(" + ", ".join(rings) + ")")
    return "MULTIPOLYGON(" + ", ".join(polys) + ")"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sgg", nargs="+", help="시군구코드 5자리")
    ap.add_argument("--all", action="store_true", help="전국 시군구 전부(meta.lawd_code) — 2026-10-24 전국 넓히기: 점 자료의 시군구를 가르려면 경계가 먼저다")
    ap.add_argument("--lawd", nargs="*", help="법정동코드 10자리로 좁히기")
    ap.add_argument("--no-geom", action="store_true")
    args = ap.parse_args()

    env = load_env(ENV)

    global DOMAIN

    DOMAIN = vworld_domain(env)

    print(f"  VWorld domain = {DOMAIN}")
    key = env.get("VWORLD_KEY", "").strip()
    if not key:
        sys.exit(".env 의 VWORLD_KEY 가 비어 있습니다")

    conn = pymssql.connect(server=env.get("DB_HOST", "127.0.0.1"),
                           port=int(env.get("DB_PORT", 11433)),
                           user=env.get("DB_USER", "sa"),
                           password=env.get("DB_PASSWORD", ""),
                           database=env.get("DB_NAME", "Teomoony"),
                           charset="UTF-8", autocommit=False)
    cur = conn.cursor()
    if args.all:
        cur.execute("""SELECT DISTINCT sgg_cd FROM meta.lawd_code
                        WHERE is_abolished = 0 AND ri_nm IS NOT NULL AND sgg_cd NOT LIKE '__000' ORDER BY sgg_cd""")
        args.sgg = [r[0] for r in cur.fetchall()]
        print(f"  전국 시군구 {len(args.sgg)}곳", flush=True)
    if not args.sgg:
        sys.exit("--sgg 또는 --all")
    want = set(args.lawd or [])
    total_new = 0
    실패 = []

    for sgg in args.sgg:
        try:
            feats = fetch_sgg(key, sgg)
        except RuntimeError as e:
            실패.append(str(e)); print(f"\n시군구 {sgg}  ! 받기 실패 — 이 구는 건너뜀(옛 값 유지)")
            continue
        print(f"\n시군구 {sgg}  수신 {len(feats)}개 리", end="")
        n = 0; 버림 = 0
        for f in feats:
            pr = f.get("properties", {}) or {}
            lawd = (pr.get("li_cd") or "").strip()
            if len(lawd) != 10 or not lawd.isdigit() or lawd.endswith("00"):
                continue
            if want and lawd not in want:
                continue
            geom = f.get("geometry") or {}
            if geom.get("type") == "Polygon":           # ★ 단일 폴리곤도 받는다(전엔 말없이 버렸다)
                geom = {"type": "MultiPolygon", "coordinates": [geom["coordinates"]]}
            if geom.get("type") != "MultiPolygon":
                버림 += 1
                continue
            coords = geom["coordinates"]
            gj = json.dumps(geom, ensure_ascii=False, separators=(",", ":"))
            minx, miny, maxx, maxy = ring_stats(coords)

            vals = dict(lawd_cd=lawd,
                        ri_nm=pr.get("li_kor_nm"), full_nm=pr.get("full_nm"),
                        geojson=gj,
                        centroid_lat=round((miny + maxy) / 2, 7),
                        centroid_lng=round((minx + maxx) / 2, 7),
                        bbox_minx=round(minx, 7), bbox_miny=round(miny, 7),
                        bbox_maxx=round(maxx, 7), bbox_maxy=round(maxy, 7))
            rh = hashlib.sha256(
                "\x1f".join(str(vals[k]) for k in sorted(vals)).encode("utf-8")).digest()

            cur.execute("""UPDATE silver.ri_boundary
                              SET is_current=0, valid_to=SYSDATETIME()
                            WHERE is_current=1 AND lawd_cd=CAST(%s AS CHAR(10)) AND row_hash<>%s""", (lawd, rh))
            cols = list(vals.keys())
            if args.no_geom:
                sql = (f"IF NOT EXISTS (SELECT 1 FROM silver.ri_boundary "
                       f"WHERE is_current=1 AND lawd_cd=CAST(%s AS CHAR(10))) "
                       f"INSERT INTO silver.ri_boundary ({', '.join(cols)}, row_hash) "
                       f"VALUES ({', '.join(['%s']*len(cols))}, %s)")
                cur.execute(sql, (lawd,) + tuple(vals[c] for c in cols) + (rh,))
            else:
                sql = (f"IF NOT EXISTS (SELECT 1 FROM silver.ri_boundary "
                       f"WHERE is_current=1 AND lawd_cd=CAST(%s AS CHAR(10))) "
                       f"INSERT INTO silver.ri_boundary ({', '.join(cols)}, geom, row_hash) "
                       f"VALUES ({', '.join(['%s']*len(cols))}, "
                       f"geometry::STGeomFromText(%s, 4326).MakeValid(), %s)")
                cur.execute(sql, (lawd,) + tuple(vals[c] for c in cols) + (wkt(coords), rh))
            n += 1
        conn.commit()
        total_new += n
        print(f"  -> {n} 적재" + (f"  ! 모양 몰라 버림 {버림}" if 버림 else ""))

    cur.execute("SELECT COUNT(*) FROM silver.ri_boundary WHERE is_current=1")
    print(f"\n리 경계 총 {cur.fetchone()[0]:,}건")
    cur.execute("""SELECT COUNT(*) FROM meta.lawd_code l
                    WHERE l.ri_nm IS NOT NULL AND l.is_abolished = 0 AND NOT EXISTS (SELECT 1 FROM silver.ri_boundary b
                                       WHERE b.is_current=1 AND b.lawd_cd = l.lawd_cd)""")
    miss = cur.fetchone()[0]
    if miss:
        print(f"  ! 경계가 없는 리 {miss:,}개 (meta.lawd_code 기준)")
    conn.close()
    if 실패:
        print("\n! 받지 못한 시군구: " + " · ".join(실패))
        sys.exit(1)


if __name__ == "__main__":
    main()
