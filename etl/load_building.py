#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
load_building - VWorld 건물 외곽선(LT_C_SPBD)을 silver.building_footprint 에 적재

  py load_building.py

동작
  1) silver.cadastral_parcel 의 bbox 를 법정동 단위로 구해서
     그 영역의 건물을 가져온다.
     - 건물 레이어는 PNU 속성이 없어서 attrFilter 를 못 쓴다.
       대신 geomFilter(BOX) 로 영역 질의한다.
  2) 건물관리번호 앞 19자리를 PNU 로 쓴다 (computed column 이 처리)
  3) 단지별 건물 수 / 최고층수 재계산

주의
  * BOX 질의는 경계에 걸친 건물을 양쪽에서 가져올 수 있다.
    건물관리번호가 PK 라 중복은 자연히 하나로 접힌다.
  * 한 번에 1000건씩 페이징한다. 밀집 지역은 페이지가 꽤 나온다.
"""
import argparse, hashlib, json, math, os, sys, time
import requests
import pymssql

HERE = os.path.dirname(os.path.abspath(__file__))
ENV  = os.path.join(HERE, "..", ".env")
VW   = "https://api.vworld.kr/req/data"
LAYER = "LT_C_SPBD"


def load_env(path):
    d = {}
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                d[k.strip()] = v.strip()
    return d


# ★ VWorld 키는 **등록 도메인에 묶인다** (2026-10-20 실측).
#   domain=localhost 로 보내면 INCORRECT_KEY 가 나고, 그런데 fetch 함수가
#   그 법정동만 건너뛰고 넘어가므로 **적재가 조용히 0건이 된다.**
#   실제로 필지가 446,040 에서 멈췄는데 끝까지 돌면 "OK" 로 보고될 뻔했다.
#   그래서 하드코딩하지 않고 .env 의 VWORLD_DOMAIN 을 읽는다 - 도메인이 또
#   바뀌어도 코드를 고치지 않는다.
def vworld_domain(env):
    return (env.get("VWORLD_DOMAIN") or "teomoony.com").strip()


DOMAIN = "teomoony.com"   # main() 에서 .env 값으로 덮어쓴다


def fetch_box(key, box, retries=3):
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
            print(f"    ! page {page}: {json.dumps(last, ensure_ascii=False)[:150]}")
            return feats
        fs = last["result"]["featureCollection"]["features"]
        feats += fs
        total = int(last.get("page", {}).get("total", 1))
        if page >= total:
            break
        page += 1
        time.sleep(0.15)
    return feats


def split_box(x0, y0, x1, y1, max_km2=8.0):
    """BOX 를 10km2 한계 아래로 쪼갠다 (2026-10-18).

    ★ VWorld 가 직접 알려준 한계다 - 짐작이 아니다:
        "geomFilter 파라미터의 값이 유효한 범위를 넘었습니다.
         유효한 파라미터 값의 범위 : polygon, box경우 요청면적이 10km2 이내"
      정릉동(1129013300) bbox 는 4.3km x 4.55km = 약 19.6km2 라 통째로 거절당했고,
      **수신 0 으로 조용히 지나갔다.** 로그에 한 줄 찍혔을 뿐 작업은 성공으로 끝났다.
      성북동(5.0km2)은 멀쩡히 받아졌으니, 큰 법정동만 골라서 비는 모양이 된다.

    ★ 8km2 로 자른다. 10 은 한계 그 자체라 경계에서 또 거절당한다 - 실측으로
      정릉동을 반으로 쪼갠 9.8km2 도 ERROR 였다. 여유를 둔다.
    """
    # 위도 37.6도 기준. 경도 1도 ~ 88km, 위도 1도 ~ 111km.
    KMX, KMY = 88.0, 111.0
    w_km = (x1 - x0) * KMX
    h_km = (y1 - y0) * KMY
    if w_km * h_km <= max_km2:
        return [(x0, y0, x1, y1)]
    # 가로/세로를 각각 몇 등분할지. 긴 쪽을 더 잘게 썬다.
    import math
    n = math.ceil(math.sqrt(w_km * h_km / max_km2))
    nx = max(1, int(math.ceil(n * (w_km / max(h_km, 1e-9)) ** 0.5)))
    ny = max(1, int(math.ceil((w_km * h_km / max_km2) / nx)))
    out = []
    for i in range(nx):
        for j in range(ny):
            out.append((x0 + (x1 - x0) * i / nx, y0 + (y1 - y0) * j / ny,
                        x0 + (x1 - x0) * (i + 1) / nx, y0 + (y1 - y0) * (j + 1) / ny))
    return out


def stats(coords):
    xs, ys = [], []
    st = [coords]
    while st:
        c = st.pop()
        if isinstance(c[0], (int, float)):
            xs.append(c[0]); ys.append(c[1])
        else:
            st.extend(c)
    return min(xs), min(ys), max(xs), max(ys)


def approx_area(mp):
    """위도 보정한 근사 면적(m2). 공식 면적이 아니라 대조용."""
    total = 0.0
    for poly in mp:
        for i, ring in enumerate(poly):
            if len(ring) < 4:
                continue
            lat0 = sum(p[1] for p in ring) / len(ring)
            k = math.cos(math.radians(lat0))
            s = 0.0
            for j in range(len(ring) - 1):
                x1, y1 = ring[j][0] * k, ring[j][1]
                x2, y2 = ring[j+1][0] * k, ring[j+1][1]
                s += x1 * y2 - x2 * y1
            a = abs(s) / 2.0 * (111320.0 ** 2)
            total += a if i == 0 else -a      # 내부 링(구멍)은 뺀다
    return round(total, 2)


def wkt(mp):
    polys = []
    for poly in mp:
        rings = ["(" + ", ".join(f"{x} {y}" for x, y in r) + ")" for r in poly]
        polys.append("(" + ", ".join(rings) + ")")
    return "MULTIPOLYGON(" + ", ".join(polys) + ")"


def _notify(title, lines):
    """끝났으면 카톡으로 알린다 (2026-10-18).

    ★ 왜 여기에 넣나
      알림은 `runlog.RunLog` 가 보내는데 그것도 `cmd == "go"` 일 때만이고,
      이 적재기들은 RunLog 를 아예 안 쓴다. 그래서 **16분짜리 작업이 끝나도
      아무 말이 없었다.** 사용자가 "카톡 알람이 안 와서" 라고 물어서 알았다.
      화면을 못 보는 쪽에서는 끝난 것과 멈춘 것이 구분되지 않는다.

    ★ 실패해도 조용히 넘어간다. 알림이 적재 기록을 방해하면 안 된다 -
      RunLog 가 지키는 원칙과 같다. 설정 전이어도 마찬가지다.
    """
    try:
        import notify
        ok, why = notify.send("[터무니] " + title + "\n" + "\n".join(lines))
        print(f"[알림] {'보냄' if ok else '안 보냄 - ' + why}")
    except Exception as e:
        print(f"[알림] 실패 - {type(e).__name__}: {e}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lawd", nargs="*", help="법정동코드 10자리. 생략하면 필지가 적재된 전부")
    ap.add_argument("--pad", type=float, default=0.0008, help="법정동 bbox 여유 (도)")
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

    cur.execute("""SELECT lawd_cd,
                          MIN(bbox_minx), MIN(bbox_miny), MAX(bbox_maxx), MAX(bbox_maxy)
                     FROM silver.cadastral_parcel
                    WHERE is_current = 1
                    GROUP BY lawd_cd ORDER BY lawd_cd""")
    boxes = cur.fetchall()
    if args.lawd:
        # 범위를 안 주면 이미 적재된 법정동을 전부 다시 내려받는다(종로구만 87개).
        want = set(args.lawd)
        boxes = [b for b in boxes if b[0] in want]
        missing = want - {b[0] for b in boxes}
        if missing:
            print(f"  ! 필지가 없는 법정동은 건너뜁니다: {', '.join(sorted(missing))}")
    if not boxes:
        sys.exit("필지가 없습니다. load_cadastral.py 를 먼저 돌리세요.")

    print(f"대상 법정동 {len(boxes)}개")
    seen = set()
    total_new = 0

    for lawd, x0, y0, x1, y1 in boxes:
        tiles = split_box(float(x0)-args.pad, float(y0)-args.pad,
                          float(x1)+args.pad, float(y1)+args.pad)
        feats = []
        for (tx0, ty0, tx1, ty1) in tiles:
            feats += fetch_box(key, f"BOX({tx0},{ty0},{tx1},{ty1})")
            if len(tiles) > 1:
                time.sleep(0.15)
        n = 0
        for f in feats:
            pr = f.get("properties", {}) or {}
            sn = (pr.get("bd_mgt_sn") or "").strip()
            if len(sn) != 25 or sn in seen:
                continue
            seen.add(sn)
            g = f.get("geometry") or {}
            if g.get("type") != "MultiPolygon":
                continue
            co = g["coordinates"]
            minx, miny, maxx, maxy = stats(co)
            flo = (pr.get("gro_flo_co") or "").strip()

            vals = dict(bd_mgt_sn=sn,
                        buld_nm=pr.get("buld_nm") or None,
                        buld_nm_dc=pr.get("buld_nm_dc") or None,
                        bul_eng_nm=pr.get("bul_eng_nm") or None,
                        buld_no=pr.get("buld_no") or None,
                        rd_nm=pr.get("rd_nm") or None,
                        sido_nm=pr.get("sido") or None,
                        sigungu_nm=pr.get("sigungu") or None,
                        emd_nm=pr.get("gu") or None,
                        gro_flo_co=int(float(flo)) if flo.replace('.','',1).isdigit() else None,
                        geojson=json.dumps(g, ensure_ascii=False, separators=(",", ":")),
                        centroid_lat=round((miny+maxy)/2, 7),
                        centroid_lng=round((minx+maxx)/2, 7),
                        bbox_minx=round(minx,7), bbox_miny=round(miny,7),
                        bbox_maxx=round(maxx,7), bbox_maxy=round(maxy,7),
                        area_m2_approx=approx_area(co))
            rh = hashlib.sha256(
                "\x1f".join(str(vals[k]) for k in sorted(vals)).encode("utf-8")).digest()

            cur.execute("""UPDATE silver.building_footprint
                              SET is_current=0, valid_to=SYSDATETIME()
                            WHERE is_current=1 AND bd_mgt_sn=%s AND row_hash<>%s""", (sn, rh))
            cols = list(vals.keys())
            if args.no_geom:
                cur.execute(
                    f"IF NOT EXISTS (SELECT 1 FROM silver.building_footprint "
                    f"WHERE is_current=1 AND bd_mgt_sn=%s) "
                    f"INSERT INTO silver.building_footprint ({', '.join(cols)}, row_hash) "
                    f"VALUES ({', '.join(['%s']*len(cols))}, %s)",
                    (sn,) + tuple(vals[c] for c in cols) + (rh,))
            else:
                cur.execute(
                    f"IF NOT EXISTS (SELECT 1 FROM silver.building_footprint "
                    f"WHERE is_current=1 AND bd_mgt_sn=%s) "
                    f"INSERT INTO silver.building_footprint ({', '.join(cols)}, geom, row_hash) "
                    f"VALUES ({', '.join(['%s']*len(cols))}, "
                    f"geometry::STGeomFromText(%s, 4326).MakeValid(), %s)",
                    (sn,) + tuple(vals[c] for c in cols) + (wkt(co), rh))
            n += 1
        conn.commit()
        total_new += n
        print(f"  {lawd}  수신 {len(feats):5d}  신규 {n:5d}"
              + (f"  (BOX {len(tiles)}조각)" if len(tiles) > 1 else ""))

    print("\n단지별 건물 집계")
    cur.execute("EXEC gold.usp_refresh_complex_building")
    conn.commit()

    cur.execute("SELECT COUNT(*) FROM silver.building_footprint WHERE is_current=1")
    print(f"  건물 총 {cur.fetchone()[0]:,}건")
    cur.execute("""SELECT COUNT(*) FROM silver.building_footprint f
                    WHERE f.is_current=1
                      AND EXISTS (SELECT 1 FROM silver.cadastral_parcel p
                                   WHERE p.pnu = f.pnu AND p.is_current=1)""")
    onpar = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM silver.building_footprint WHERE is_current=1")
    tot = cur.fetchone()[0]
    print(f"  PNU 가 적재된 필지와 일치: {onpar:,}/{tot:,} ({100.0*onpar/max(tot,1):.1f}%)")
    cur.execute("""SELECT SUM(CASE WHEN bld_cnt>0 THEN 1 ELSE 0 END), COUNT(*),
                          SUM(bld_cnt), SUM(dong_cnt) FROM gold.complex""")
    withb, allc, bsum, dsum = cur.fetchone()
    print(f"  건물이 붙은 단지: {withb or 0:,}/{allc:,}")
    print(f"  건물 폴리곤 합 {bsum or 0:,} vs 대장 동 수 합 {dsum or 0:,}")
    _notify("건물 외곽선 적재 완료",
            [f"법정동 {len(boxes):,}개 (신규 {total_new:,}건)",
             f"건물 총 {tot:,}건",
             f"건물이 붙은 단지 {withb or 0:,}/{allc:,}"])
    conn.close()


if __name__ == "__main__":
    main()
