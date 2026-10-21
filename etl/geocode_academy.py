# -*- coding: utf-8 -*-
"""학원 좌표 붙이기 — VWorld 지오코더  2026-10-20

  py geocode_academy.py              아직 안 한 것 전부
  py geocode_academy.py --limit 50   조금만 (처음 확인용)
  py geocode_academy.py --retry-fail FAIL 로 남은 것만 다시

★ 인자는 추측하지 않고 실제 주소로 찔러 확인했다(2026-10-20):
    https://api.vworld.kr/req/address
    service=address request=getcoord version=2.0 crs=epsg:4326
    type=ROAD format=json refine=true simple=false key=... address=...
  돌아오는 것: response.status / response.result.point.{x,y} / response.refined.text
  domain 인자는 필요 없다.

★ 주소마다 한 번만 부른다. 서울 학원 25,512곳이지만 **서로 다른 도로명주소는
  12,366개**다(한 건물에 평균 2곳). 같은 주소는 한 번 받아 전부에 쓴다.

★★ 조용히 틀린 좌표는 NULL 보다 나쁘다 (정책 1장)
  지오코더는 '비슷한 주소' 를 돌려줄 수 있다. 그래서 정제 주소(refined.text)가
  **넣은 주소를 그대로 품고 있는지** 본다. 아니면 OK 가 아니라 MISMATCH 로 적고
  좌표를 **넣지 않는다.** 지도에 안 뜨는 건 드러나지만, 엉뚱한 곳에 뜨는 건
  아무도 모른다.

★★ 한도 초과를 NOT_FOUND 로 적지 않는다
  status 가 OK/NOT_FOUND 가 아닌 것은 전부 FAIL 로 두고(다시 할 수 있게),
  연속 FAIL 이 20번이면 **멈춘다.** 한도가 걸린 걸 '주소 없음' 으로 적어버리면
  12,366곳이 조용히 빈 채로 남는다.

★ 한반도 밖 좌표는 좌표만 비운다(RANGE). 고치려 들지 않는다.
"""
import argparse, io, os, sys, time
import requests, pymssql

HERE = os.path.dirname(os.path.abspath(__file__))
ENV  = os.path.join(HERE, "..", ".env")
URL  = "https://api.vworld.kr/req/address"
KR   = (32.0, 39.7, 124.0, 132.2)      # lat_min, lat_max, lon_min, lon_max
BASE = dict(service="address", request="getcoord", version="2.0",
            crs="epsg:4326", type="ROAD", format="json",
            refine="true", simple="false")


def env():
    d = {}
    for line in io.open(ENV, encoding="utf-8-sig"):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1); d[k.strip()] = v.strip()
    return d


def 같은주소인가(넣은, 정제):
    """정제 주소가 넣은 주소를 그대로 품고 있나.
       '서울특별시 강남구 개포로82길 7' -> '서울특별시 강남구 개포로82길 7 (개포동)' 은 OK.
       공백만 접어서 비교한다 — 괄호 안의 법정동·건물명은 덧붙는 정보라 괜찮다."""
    if not 정제: return False
    접기 = lambda s: " ".join(str(s).split())
    return 접기(넣은) in 접기(정제)


def 한번(key, addr):
    """돌려주는 것: (status, lat, lon, refined)"""
    p = dict(BASE); p["key"] = key; p["address"] = addr
    try:
        j = requests.get(URL, params=p, timeout=30).json()
    except Exception as e:
        return f"FAIL:{type(e).__name__}", None, None, None
    r = j.get("response") or {}
    st = r.get("status")
    if st == "NOT_FOUND":
        return "NOT_FOUND", None, None, None
    if st != "OK":
        # ★ 한도·키 오류를 '주소 없음' 으로 적지 않는다
        err = (r.get("error") or {})
        return f"FAIL:{st}:{err.get('text') or err.get('code') or ''}"[:60], None, None, None
    pt = (r.get("result") or {}).get("point") or {}
    정제 = (r.get("refined") or {}).get("text")
    try:
        lon, lat = float(pt.get("x")), float(pt.get("y"))
    except (TypeError, ValueError):
        return "FAIL:NO_POINT", None, None, 정제
    if not (KR[0] <= lat <= KR[1] and KR[2] <= lon <= KR[3]):
        return "RANGE", None, None, 정제
    if not 같은주소인가(addr, 정제):
        return "MISMATCH", None, None, 정제
    return "OK", lat, lon, 정제


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0, help="주소 몇 개만 (0=전부)")
    ap.add_argument("--retry-fail", action="store_true", help="FAIL 로 남은 것만")
    ap.add_argument("--sleep", type=float, default=0.12)
    a = ap.parse_args()

    e = env()
    key = e.get("VWORLD_KEY", "").strip()
    if not key: sys.exit(".env 에 VWORLD_KEY 가 없습니다")

    conn = pymssql.connect(server=e.get("DB_HOST", "127.0.0.1"),
                           port=int(e.get("DB_PORT", 11433)),
                           user=e.get("DB_USER", "sa"),
                           password=e.get("DB_PASSWORD", ""),
                           database=e.get("DB_NAME", "Teomoony"),
                           charset="UTF-8", autocommit=False)
    cur = conn.cursor()

    조건 = ("geocode_status LIKE 'FAIL%'" if a.retry_fail
            else "(geocode_status IS NULL OR geocode_status LIKE 'FAIL%')")
    cur.execute(f"""SELECT road_addr, COUNT(*)
                      FROM silver.academy
                     WHERE is_current = 1 AND road_addr IS NOT NULL AND {조건}
                     GROUP BY road_addr ORDER BY road_addr""")
    일감 = cur.fetchall()
    if a.limit: 일감 = 일감[:a.limit]
    if not 일감:
        print("할 일이 없습니다 (전부 처리됨)"); conn.close(); return
    총행 = sum(n for _, n in 일감)
    print(f"주소 {len(일감):,}개 · 그에 걸린 행 {총행:,}개", flush=True)

    셈 = {}
    연속실패 = 0
    t0 = time.time()
    for i, (addr, n) in enumerate(일감, 1):
        st, lat, lon, 정제 = 한번(key, addr)
        뿌리 = st.split(":")[0]
        셈[뿌리] = 셈.get(뿌리, 0) + n

        if 뿌리 == "FAIL":
            연속실패 += 1
            if 연속실패 >= 20:
                conn.commit()
                print(f"\n★ 연속 FAIL 20회 — 멈춥니다. 마지막: {st}")
                print("  한도 초과거나 키 문제일 수 있습니다. 고친 뒤 --retry-fail 로 이어갑니다.")
                break
        else:
            연속실패 = 0

        cur.execute("""UPDATE silver.academy
                          SET lat = %s, lon = %s,
                              geog = CASE WHEN %s IS NOT NULL
                                          THEN geography::Point(%s, %s, 4326) END,
                              geocode_status = %s, geocode_at = SYSDATETIME(),
                              geocode_text = %s
                        WHERE is_current = 1 AND road_addr = %s""",
                    (lat, lon, lat, lat, lon, st[:20], 정제, addr))
        if i % 200 == 0:
            conn.commit()
            초 = time.time() - t0
            남 = (len(일감) - i) * (초 / i)
            print(f"  {i:,}/{len(일감):,}  OK {셈.get('OK',0):,} · "
                  f"못찾음 {셈.get('NOT_FOUND',0):,} · 다른곳 {셈.get('MISMATCH',0):,} · "
                  f"실패 {셈.get('FAIL',0):,}  (남은 시간 약 {int(남//60)}분)", flush=True)
        time.sleep(a.sleep)
    conn.commit()

    print(f"\n끝 — {int((time.time()-t0)//60)}분 {int((time.time()-t0)%60)}초")
    for k in ("OK", "NOT_FOUND", "MISMATCH", "RANGE", "FAIL"):
        if 셈.get(k): print(f"  {k:10s} {셈[k]:,}행")
    if 셈.get("MISMATCH"):
        print("  ★ MISMATCH 는 지오코더가 **다른 주소**를 돌려준 것입니다 —")
        print("    좌표를 넣지 않았습니다. geocode_text 와 road_addr 를 나란히 보세요.")
    if 셈.get("NOT_FOUND") or 셈.get("FAIL") or 셈.get("MISMATCH"):
        print("  ★ 좌표가 없는 학원은 지도·거리에서 빠집니다 — 없는 게 아니라 못 보는 것입니다.")
        print("    화면은 gold.v_academy_gap 으로 그 수를 반드시 같이 적어야 합니다.")

    cur.execute("""SELECT geocode_status, COUNT(*) FROM silver.academy
                    WHERE is_current = 1 GROUP BY geocode_status""")
    print("\n표 전체 상태:")
    for k, n in cur.fetchall():
        print(f"  {str(k):12s} {n:,}")
    print("\n★ 단지 좌표는 필지에서 오므로, 필지가 없는 구에서는 학원이 붙을 단지가 없습니다.")
    conn.close()


if __name__ == "__main__":
    main()
