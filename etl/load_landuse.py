#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
load_landuse - VWorld 용도지역(LT_C_UQ111) 을 silver.land_use_zone 에 적재

  py load_landuse.py                 (필지가 적재된 법정동 전부)
  py load_landuse.py --lawd 1129010300 ...

왜 이렇게 하나
  * 이 레이어는 **PNU 가 없다.** 속성이 uname/dyear/dnum/sido_name/sigg_name
    다섯뿐이다. attrFilter 는 단독으로 못 쓴다(sigg_name 은 '단일검색' 속성이
    아니라고 거절한다). 그래서 **geomFilter(BOX)** 로 받는다 - 건물과 같다.
  * BOX 는 10km2 를 넘으면 거절당한다(11-30). load_building 의 split_box 를
    **그대로 가져다 쓴다.** 같은 규칙을 두 군데 적으면 한쪽만 고치게 된다
    - 오늘 bld_cnt 로 그 값을 치렀다(11-38).
  * 자연키가 없어 **속성+좌표의 sha256** 을 키로 쓴다. 지오메트리가 곧 정체성이다.
  * 큰 폴리곤이라 법정동 여러 개에서 같은 것이 몇 번씩 온다. zone_key 로 접는다.

주의
  * VWorld 의 **에러 응답 JSON 이 깨져서 올 때가 있다** (text 안에 이스케이프
    안 된 따옴표가 들어온다). .json() 이 거기서 죽으므로 직접 감싼다.
"""
import argparse, hashlib, json, os, sys, time
import requests
import pymssql

from load_building import load_env, split_box, stats, approx_area, wkt

HERE  = os.path.dirname(os.path.abspath(__file__))
ENV   = os.path.join(HERE, "..", ".env")
VW    = "https://api.vworld.kr/req/data"
LAYER = "LT_C_UQ111"



# ★ VWorld 키는 **등록 도메인에 묶인다** (2026-10-20 실측).
#   domain=localhost -> INCORRECT_KEY. 그런데 fetch 가 그 단위만 건너뛰고 넘어가서
#   **적재가 조용히 0건이 된다.** 실제로 필지가 446,040 에서 멈췄는데 끝까지 돌면
#   "OK" 로 보고될 뻔했다. 하드코딩하지 않고 .env 의 VWORLD_DOMAIN 을 읽는다.
def vworld_domain(env):
    return (env.get("VWORLD_DOMAIN") or "teomoony.com").strip()


DOMAIN = "teomoony.com"   # main() 에서 .env 값으로 덮어쓴다


def fetch_box(key, box, retries=3):
    """BOX 한 조각을 페이징해서 전부 받는다. 깨진 JSON 에 죽지 않는다."""
    feats, page = [], 1
    while True:
        p = {"service": "data", "version": "2.0", "request": "GetFeature",
             "key": key, "data": LAYER, "geomFilter": box,
             "geometry": "true", "attribute": "true", "crs": "EPSG:4326",
             "format": "json", "size": "1000", "page": str(page),
             "domain": DOMAIN}
        last = None
        for a in range(retries):
            try:
                r = requests.get(VW, params=p, timeout=120)
                try:
                    j = r.json().get("response", {})
                except ValueError:
                    # ★ 에러 본문이 깨진 JSON 인 경우가 있다. 상태만 긁어낸다.
                    t = r.text[:400]
                    j = {"status": "BROKEN_JSON", "error": t}
                last = j
                if j.get("status") == "OK":
                    break
                if j.get("status") == "NOT_FOUND":
                    return feats
            except Exception as e:
                last = {"status": "EXCEPTION", "error": str(e)}
            time.sleep(1.5 * (a + 1))
        if not last or last.get("status") != "OK":
            print(f"    ! page {page}: {json.dumps(last, ensure_ascii=False)[:160]}")
            return feats
        feats += last["result"]["featureCollection"]["features"]
        if page >= int(last.get("page", {}).get("total", 1)):
            break
        page += 1
        time.sleep(0.15)
    return feats


def _notify(title, lines):
    """끝났으면 카톡으로 알린다. 실패해도 조용히 넘어간다(11-33)."""
    try:
        import notify
        ok, why = notify.send("[터무니] " + title + "\n" + "\n".join(lines))
        print(f"[알림] {'보냄' if ok else '안 보냄 - ' + str(why)}")
    except Exception as e:
        print(f"[알림] 실패 - {type(e).__name__}: {e}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lawd", nargs="*", help="법정동코드 10자리. 생략하면 필지가 적재된 전부")
    ap.add_argument("--pad", type=float, default=0.0008)
    ap.add_argument("--close-stale", action="store_true",
                    help="이번에 못 본 구역을 닫는다. **그 구를 전부 받았을 때만** 쓴다")
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

    cur.execute("""SELECT lawd_cd,
                          MIN(bbox_minx), MIN(bbox_miny), MAX(bbox_maxx), MAX(bbox_maxy)
                     FROM silver.cadastral_parcel
                    WHERE is_current = 1
                    GROUP BY lawd_cd ORDER BY lawd_cd""")
    boxes = cur.fetchall()
    if args.lawd:
        want = set(args.lawd)
        boxes = [b for b in boxes if b[0] in want]
        missing = want - {b[0] for b in boxes}
        if missing:
            print(f"  ! 필지가 없는 법정동은 건너뜁니다: {', '.join(sorted(missing))}")
    if not boxes:
        sys.exit("필지가 없습니다. load_cadastral.py 를 먼저 돌리세요.")

    print(f"대상 법정동 {len(boxes)}개  (레이어 {LAYER} 용도지역)")
    seen, siggs, total_new, total_recv = set(), set(), 0, 0

    for lawd, x0, y0, x1, y1 in boxes:
        tiles = split_box(float(x0)-args.pad, float(y0)-args.pad,
                          float(x1)+args.pad, float(y1)+args.pad)
        feats = []
        for (tx0, ty0, tx1, ty1) in tiles:
            feats += fetch_box(key, f"BOX({tx0},{ty0},{tx1},{ty1})")
            if len(tiles) > 1:
                time.sleep(0.15)
        total_recv += len(feats)
        n = 0
        for f in feats:
            pr = f.get("properties", {}) or {}
            g = f.get("geometry") or {}
            if g.get("type") != "MultiPolygon":
                continue
            co = g["coordinates"]
            w = wkt(co)
            kraw = "\x1f".join([str(pr.get(k) or "") for k in
                               ("uname", "dyear", "dnum", "sido_name", "sigg_name")] + [w])
            zk = hashlib.sha256(kraw.encode("utf-8")).hexdigest()
            if zk in seen:
                continue
            seen.add(zk)
            if pr.get("sigg_name"):
                siggs.add(pr["sigg_name"])
            minx, miny, maxx, maxy = stats(co)
            vals = dict(zone_key=zk,
                        uname=pr.get("uname") or None,
                        dyear=(pr.get("dyear") or None),
                        dnum=(pr.get("dnum") or None),
                        sido_name=pr.get("sido_name") or None,
                        sigg_name=pr.get("sigg_name") or None,
                        geojson=json.dumps(g, ensure_ascii=False, separators=(",", ":")),
                        centroid_lat=round((miny+maxy)/2, 7),
                        centroid_lng=round((minx+maxx)/2, 7),
                        bbox_minx=round(minx, 7), bbox_miny=round(miny, 7),
                        bbox_maxx=round(maxx, 7), bbox_maxy=round(maxy, 7),
                        area_m2_approx=approx_area(co))
            rh = hashlib.sha256(
                "\x1f".join(str(vals[k]) for k in sorted(vals)).encode("utf-8")).digest()
            cols = list(vals.keys())
            cur.execute(
                f"IF NOT EXISTS (SELECT 1 FROM silver.land_use_zone "
                f"WHERE is_current=1 AND zone_key=%s) "
                f"INSERT INTO silver.land_use_zone ({', '.join(cols)}, geom, row_hash) "
                f"VALUES ({', '.join(['%s']*len(cols))}, "
                f"geometry::STGeomFromText(%s, 4326).MakeValid(), %s)",
                (zk,) + tuple(vals[c] for c in cols) + (w, rh))
            n += 1
        conn.commit()
        total_new += n
        print(f"  {lawd}  수신 {len(feats):5d}  신규 {n:4d}"
              + (f"  (BOX {len(tiles)}조각)" if len(tiles) > 1 else ""))

    # ---- 이번에 못 본 구역 ----
    # ★ 기본은 **닫지 않는다.** BOX 는 사각형이라 옆 구를 물고 들어온다 -
    #   장위동 하나만 받았는데 sigg 에 강북구·노원구가 같이 잡혔다(probe).
    #   그 상태에서 'sigg 안에서 못 본 건 닫는다' 를 돌리면, 강북구를 제대로
    #   받아 둔 행이 **장위동 적재 때문에 닫힌다.** 조용히 틀리는 쪽이다.
    #   그래서 셈만 하고, 닫는 건 --close-stale 을 **일부러 줄 때만** 한다.
    closed, stale = 0, 0
    if siggs:
        ph = ", ".join(["%s"] * len(siggs))
        cur.execute(f"""SELECT COUNT(*) FROM silver.land_use_zone
                         WHERE is_current = 1 AND sigg_name IN ({ph})
                           AND zone_key NOT IN (SELECT value FROM STRING_SPLIT(%s, ','))""",
                    tuple(siggs) + (",".join(seen),))
        stale = cur.fetchone()[0]
        if args.close_stale:
            cur.execute(f"""UPDATE silver.land_use_zone
                               SET is_current = 0, valid_to = SYSDATETIME()
                             WHERE is_current = 1 AND sigg_name IN ({ph})
                               AND zone_key NOT IN (SELECT value FROM STRING_SPLIT(%s, ','))""",
                        tuple(siggs) + (",".join(seen),))
            closed = cur.rowcount
            conn.commit()
        print(f"\n  범위({', '.join(sorted(siggs))}) 안에서 이번에 못 본 구역 {stale:,}건"
              + (f" -> {closed:,}건 닫음" if args.close_stale
                 else "  (닫지 않았습니다. 닫으려면 --close-stale)"))

    cur.execute("SELECT COUNT(*) FROM silver.land_use_zone WHERE is_current=1")
    tot = cur.fetchone()[0]
    cur.execute("""SELECT TOP 8 uname, COUNT(*) FROM silver.land_use_zone
                    WHERE is_current=1 GROUP BY uname ORDER BY COUNT(*) DESC""")
    print("\n용도지역 분포")
    for u, c in cur.fetchall():
        print(f"  {u or '(빈값)':<24} {c:,}")
    print(f"\n  용도지역 총 {tot:,}건  (수신 {total_recv:,} / 신규 {total_new:,})")

    _notify("용도지역 적재 완료",
            [f"법정동 {len(boxes):,}개",
             f"용도지역 총 {tot:,}건 (신규 {total_new:,})",
             f"못 본 구역 {stale:,}건 (닫음 {closed:,})"])
    conn.close()


if __name__ == "__main__":
    main()
