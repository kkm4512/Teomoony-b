#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
load_cadastral - VWorld 연속지적도를 silver.cadastral_parcel 에 적재

  py load_cadastral.py              # 단지가 참조하는 법정동 전부
  py load_cadastral.py --lawd 1111010100 1111011100

동작
  1) gold.complex_pnu 에서 필요한 법정동코드(PNU 앞 10자리)를 뽑는다
  2) 법정동 단위로 VWorld 를 호출한다 (pnu:like:<법정동코드>)
     - 필지를 하나씩 부르지 않는다. 한 법정동이 1회 호출로 끝난다.
  3) silver.cadastral_parcel 에 SCD2 로 적재
  4) gold.usp_refresh_complex_geo 로 단지 좌표 재계산

주의
  * crs=EPSG:4326 으로 받는다. 위경도 그대로라 변환이 필요 없다.
  * 부속지번이 다른 법정동을 가리키는 경우가 있다 (단지가 행정경계를
    넘나든다). 1) 단계가 그 법정동까지 자동으로 포함한다.
"""
import argparse, hashlib, json, os, sys, time
import requests
import pymssql

HERE = os.path.dirname(os.path.abspath(__file__))
ENV  = os.path.join(HERE, "..", ".env")
VW   = "https://api.vworld.kr/req/data"
LAYER = "LP_PA_CBND_BUBUN"


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


def fetch_lawd(key, lawd, retries=3):
    """법정동 하나의 필지를 전부 가져온다 (페이지당 1000)."""
    feats, page = [], 1
    while True:
        p = {"service": "data", "version": "2.0", "request": "GetFeature",
             "key": key, "data": LAYER, "attrFilter": f"pnu:like:{lawd}",
             "geometry": "true", "attribute": "true", "crs": "EPSG:4326",
             "format": "json", "size": "1000", "page": str(page),
             "domain": DOMAIN}
        last = None
        for a in range(retries):
            try:
                r = requests.get(VW, params=p, timeout=120)
                j = r.json().get("response", {})
                last = j
                if j.get("status") == "OK":
                    break
                if j.get("status") == "NOT_FOUND":
                    return feats
            except Exception as e:
                last = {"status": "EXCEPTION", "error": str(e)}
            time.sleep(1.5 * (a + 1))
        if not last or last.get("status") != "OK":
            print(f"    ! {lawd} page {page}: {json.dumps(last, ensure_ascii=False)[:160]}")
            return feats
        fs = last["result"]["featureCollection"]["features"]
        feats += fs
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
    """MultiPolygon GeoJSON -> WKT"""
    polys = []
    for poly in mp:
        rings = []
        for ring in poly:
            pts = ", ".join(f"{x} {y}" for x, y in ring)
            rings.append("(" + pts + ")")
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
    ap.add_argument("--lawd", nargs="*", help="법정동코드 10자리. 생략하면 단지가 참조하는 전부")
    ap.add_argument("--no-geom", action="store_true", help="geometry 컬럼 생략 (GeoJSON 만 저장)")
    ap.add_argument("--no-refresh", action="store_true",
                    help="끝의 단지 좌표 재계산 · 전체 집계를 건너뛴다(2026-10-25 전국 적재 — 읍면동마다 3,500번 돌면 안 된다. 다 넣고 한 번)")
    ap.add_argument("--skip-loaded", action="store_true",
                    help="이미 필지가 들어온 법정동은 건너뛴다 (새 구를 빨리 채울 때)")
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

    if args.lawd:
        lawds = args.lawd
    else:
        cur.execute("SELECT DISTINCT LEFT(pnu,10) FROM gold.complex_pnu ORDER BY 1")
        lawds = [r[0] for r in cur.fetchall()]

    # ★ --skip-loaded: 이미 들어온 법정동을 건너뛴다 (2026-10-20)
    #   이 적재기는 대상을 코드 순으로 도는데, 앞쪽(종로·성북·은평·서초)이 이미
    #   들어와 있으면 25만 필지를 **다시 받아 재버전만** 한다. 오늘 그걸로 한 시간을
    #   썼고, 그 구간 동안 parcels 가 안 움직여서 "멈췄나" 를 의심하게 만들었다.
    #   ★ 건너뛰면 그 법정동의 **갱신(공시지가·경계 변경)은 반영되지 않는다.**
    #     그래서 기본값은 꺼둔다 — 새 구를 빨리 채울 때만 쓴다.
    #     건너뛴 수를 반드시 찍는다. 조용히 줄이지 않는다.
    건너뜀 = 0
    if args.skip_loaded and not args.lawd:
        cur.execute("""SELECT DISTINCT lawd_cd FROM silver.cadastral_parcel
                        WHERE is_current = 1""")
        이미 = {r[0].strip() for r in cur.fetchall() if r[0]}
        남길 = [x for x in lawds if x not in 이미]
        건너뜀 = len(lawds) - len(남길)
        lawds = 남길
        print(f"★ --skip-loaded: 이미 들어온 법정동 {건너뜀}곳을 건너뜁니다 "
              f"(그곳의 공시지가·경계 갱신은 반영되지 않습니다)")
    if not lawds:
        sys.exit("대상 법정동이 없습니다. 먼저 건축물대장을 적재하고 build 를 돌리세요.")

    print(f"대상 법정동 {len(lawds)}개: {', '.join(lawds)}")
    total_new = 0

    for lawd in lawds:
        feats = fetch_lawd(key, lawd)
        print(f"  {lawd}  {len(feats):5d} 필지", end="")
        n = 0
        for f in feats:
            pr = f.get("properties", {}) or {}
            pnu = (pr.get("pnu") or "").strip()
            if len(pnu) != 19:
                continue
            geom = f.get("geometry") or {}
            if geom.get("type") != "MultiPolygon":
                continue
            coords = geom["coordinates"]
            gj = json.dumps(geom, ensure_ascii=False, separators=(",", ":"))
            minx, miny, maxx, maxy = ring_stats(coords)
            jiga = (pr.get("jiga") or "").strip()
            jiga = float(jiga) if jiga.replace(".", "", 1).isdigit() else None

            vals = dict(pnu=pnu, jibun=pr.get("jibun"), bonbun=pr.get("bonbun"),
                        bubun=pr.get("bubun"), addr=pr.get("addr"), jiga=jiga,
                        gosi_year=pr.get("gosi_year"), gosi_month=pr.get("gosi_month"),
                        geojson=gj,
                        centroid_lat=round((miny + maxy) / 2, 7),
                        centroid_lng=round((minx + maxx) / 2, 7),
                        bbox_minx=round(minx, 7), bbox_miny=round(miny, 7),
                        bbox_maxx=round(maxx, 7), bbox_maxy=round(maxy, 7))
            rh = hashlib.sha256(
                "\x1f".join(str(vals[k]) for k in sorted(vals)).encode("utf-8")).digest()

            cur.execute("""UPDATE silver.cadastral_parcel
                              SET is_current=0, valid_to=SYSDATETIME()
                            WHERE is_current=1 AND pnu=%s AND row_hash<>%s""", (pnu, rh))
            cols = list(vals.keys())
            if args.no_geom:
                sql = (f"IF NOT EXISTS (SELECT 1 FROM silver.cadastral_parcel "
                       f"WHERE is_current=1 AND pnu=%s) "
                       f"INSERT INTO silver.cadastral_parcel ({', '.join(cols)}, row_hash) "
                       f"VALUES ({', '.join(['%s']*len(cols))}, %s)")
                cur.execute(sql, (pnu,) + tuple(vals[c] for c in cols) + (rh,))
            else:
                sql = (f"IF NOT EXISTS (SELECT 1 FROM silver.cadastral_parcel "
                       f"WHERE is_current=1 AND pnu=%s) "
                       f"INSERT INTO silver.cadastral_parcel ({', '.join(cols)}, geom, row_hash) "
                       f"VALUES ({', '.join(['%s']*len(cols))}, "
                       f"geometry::STGeomFromText(%s, 4326).MakeValid(), %s)")
                cur.execute(sql, (pnu,) + tuple(vals[c] for c in cols) + (wkt(coords), rh))
            n += 1
        conn.commit()
        total_new += n
        print(f"  -> {n} 적재")

    if args.no_refresh:
        print(f"\n새 필지 {total_new:,} — 단지 좌표 재계산은 건너뜀(--no-refresh)"); return
    print("\n단지 좌표 재계산")
    cur.execute("EXEC gold.usp_refresh_complex_geo")
    conn.commit()

    cur.execute("SELECT COUNT(*) FROM silver.cadastral_parcel WHERE is_current=1")
    tot_parcel = cur.fetchone()[0]
    print(f"  필지 총 {tot_parcel:,}건")
    cur.execute("""SELECT COUNT(*), SUM(CASE WHEN centroid_lat IS NOT NULL THEN 1 ELSE 0 END)
                     FROM gold.complex""")
    tot, hit = cur.fetchone()
    print(f"  단지 {tot:,}개 중 좌표 확보 {hit:,}개 ({100.0*hit/max(tot,1):.1f}%)")
    cur.execute("""SELECT SUM(parcel_hit), SUM(pnu_cnt) FROM gold.complex""")
    h, t = cur.fetchone()
    print(f"  필지 매칭 {h or 0:,}/{t or 0:,} ({100.0*(h or 0)/max(t or 1,1):.1f}%)")
    _notify("필지 적재 완료",
            [f"법정동 {len(lawds):,}개",
             f"필지 총 {tot_parcel:,}건",
             f"단지 좌표 확보 {hit:,}/{tot:,} ({100.0*hit/max(tot,1):.1f}%)"])
    conn.close()


if __name__ == "__main__":
    main()
