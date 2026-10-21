#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
load_bus - 버스정류소를 silver.bus_stop 에 적재

  py load_bus.py --cities              (도시 목록만 찍고 끝. 코드를 추측하지 않는다)
  py load_bus.py --probe --city 서울   (1페이지만 떠서 생김새를 본다)
  py load_bus.py --city 서울 경기      (이름으로 고른다)
  py load_bus.py                       (전국)

출처 / 라이선스
  국토교통부_(TAGO)_버스정류소정보 (data.go.kr 15096280, 전국버스정류소표준데이터)
  https://apis.data.go.kr/1613000/BusSttnInfoInqireService
  **이용허락범위 제한 없음** · 자동승인 · 개발계정 10,000건/일

★ 왜 좌표 반경(getCrdntPrxmtSttnList) 을 안 쓰나
  반경 500m 고정이라 단지마다 한 번씩 불러야 한다 - 단지 2,375개면 2,375회다.
  어제 상권에서 똑같은 짓을 해서 **133회 중 96%가 중복**이었다(11-46).
  `getSttnNoList` 는 **도시 하나를 통째로** 준다. 서울이 1만여 개면 11회다.

★ 도시코드는 추측하지 않는다
  `getCtyCodeList` 가 코드와 이름을 같이 준다. 이름으로 고른다.
  샘플에 보인 '25' 가 대전이라는 식의 추측은 하지 않는다.

★ 경유노선('몇 번 버스')은 여기 없다
  `getSttnThrghRouteList` 는 **정류소마다 한 번**이라 지금은 안 받는다.
  받기 전까지 화면에서 버스 번호를 말하지 않는다.
"""
import argparse, hashlib, os, sys, time
import requests
import pymssql

from load_building import load_env

HERE = os.path.dirname(os.path.abspath(__file__))
ENV  = os.path.join(HERE, "..", ".env")
BASE = "https://apis.data.go.kr/1613000/BusSttnInfoInqireService"


def _notify(title, lines):
    try:
        import notify
        ok, why = notify.send("[터무니] " + title + "\n" + "\n".join(lines))
        print(f"[알림] {'보냄' if ok else '안 보냄 - ' + str(why)}")
    except Exception as e:
        print(f"[알림] 실패 - {type(e).__name__}: {e}")


def call(op, key, params, page_for_guard=None, retries=3):
    """한 번 부른다. **에러 봉투와 빈 1페이지는 조용히 넘기지 않는다.**
       (2026-10-19 학교 적재에서 `response` 래퍼가 없어 0건으로 끝난 적이 있다.
        그래서 래퍼 유무를 둘 다 받고, 정상인데 비면 멈춘다.)"""
    p = dict(params); p["serviceKey"] = key; p["_type"] = "json"
    last = None
    for t in range(retries):
        try:
            r = requests.get(f"{BASE}/{op}", params=p, timeout=120)
            j = r.json()
        except Exception as e:
            last = e
            time.sleep(2 * (t + 1))
            continue
        if "OpenAPI_ServiceResponse" in j:
            h = j["OpenAPI_ServiceResponse"].get("cmmMsgHeader", {})
            sys.exit(f"API 거절: {h.get('errMsg')} ({h.get('returnAuthMsg')})")
        resp = j.get("response") or j          # 래퍼가 없는 API 도 있다
        head = resp.get("header") or {}
        code = str(head.get("resultCode", ""))
        if code not in ("", "00", "0"):
            if code in ("03", "3"):            # NODATA
                return [], 0
            sys.exit(f"API 오류 {code}: {head.get('resultMsg')}")
        body = resp.get("body") or {}
        items = body.get("items") or []
        if isinstance(items, dict):
            items = items.get("item") or []
        if isinstance(items, dict):
            items = [items]
        total = int(body.get("totalCount") or 0)
        if page_for_guard == 1 and total > 0 and not items:
            sys.exit("totalCount 는 있는데 1페이지가 비었다 - 응답 구조 확인하라.\n"
                     "  최상위 키: " + ", ".join(sorted(j.keys())))
        return items, total
    sys.exit(f"호출 실패: {last}")


def cities(key):
    items, _ = call("getCtyCodeList", key, {"numOfRows": 1000, "pageNo": 1})
    out = []
    for r in items:
        out.append((str(r.get("citycode") or r.get("cityCode") or "").strip(),
                    (r.get("cityname") or r.get("cityName") or "").strip()))
    return [c for c in out if c[0]]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cities", action="store_true", help="도시 목록만 찍는다")
    ap.add_argument("--probe", action="store_true", help="고른 도시 1페이지만 본다")
    ap.add_argument("--city", nargs="*", default=[], help="도시 이름 일부 (예: 서울 경기)")
    ap.add_argument("--rows", type=int, default=1000)
    args = ap.parse_args()

    env = load_env(ENV)
    key = env.get("DATA_GO_KR_KEY", "").strip()
    if not key:
        sys.exit(".env 의 DATA_GO_KR_KEY 가 비어 있습니다")

    cs = cities(key)
    print(f"도시 {len(cs)}곳")
    if args.cities:
        for cd, nm in cs:
            print(f"  {cd:<6} {nm}")
        return
    if args.city:
        want = [w for w in args.city]
        cs = [c for c in cs if any(w in c[1] for w in want)]
        if not cs:
            sys.exit(f"이름에 {args.city} 가 들어간 도시가 없습니다. --cities 로 목록을 보세요.")
    print("대상: " + ", ".join(f"{nm}({cd})" for cd, nm in cs))

    if args.probe:
        cd, nm = cs[0]
        items, total = call("getSttnNoList", key,
                            {"cityCode": cd, "numOfRows": 3, "pageNo": 1}, 1)
        print(f"\n{nm}({cd}) 총 {total:,}건")
        print("--- 1건의 생김새 (추측하지 않고 눈으로 본다) ---")
        if items:
            for k, v in items[0].items():
                print(f"  {k:<14} {v!r}")
        else:
            print("  (빈 응답)")
        return

    conn = pymssql.connect(server=env.get("DB_HOST", "127.0.0.1"),
                           port=int(env.get("DB_PORT", 11433)),
                           user=env.get("DB_USER", "sa"),
                           password=env.get("DB_PASSWORD", ""),
                           database=env.get("DB_NAME", "Teomoony"),
                           charset="UTF-8", autocommit=False)
    cur = conn.cursor()
    today = time.strftime("%Y%m%d")
    n_new = n_chg = calls = recv = no_xy = 0

    for cd, nm in cs:
        page, got = 1, 0
        while True:
            items, total = call("getSttnNoList", key,
                                {"cityCode": cd, "numOfRows": args.rows,
                                 "pageNo": page}, page)
            calls += 1
            if not items:
                break
            recv += len(items)
            got += len(items)
            for r in items:
                nid = str(r.get("nodeid") or "").strip()
                if not nid:
                    continue
                try:
                    lat = float(r.get("gpslati")); lon = float(r.get("gpslong"))
                except Exception:
                    lat = lon = None
                if lat is None:
                    no_xy += 1
                vals = dict(
                    city_code=cd, city_nm=nm, node_id=nid,
                    node_nm=(r.get("nodenm") or "").strip() or None,
                    node_no=(str(r.get("nodeno") or "").strip() or None),
                    lat=round(lat, 8) if lat is not None else None,
                    lon=round(lon, 8) if lon is not None else None,
                    collected_at=today)
                rh = hashlib.sha256(
                    "\x1f".join(str(vals[k]) for k in sorted(vals) if k != "collected_at")
                    .encode("utf-8")).digest()
                cur.execute("""UPDATE silver.bus_stop
                                  SET is_current = 0, valid_to = SYSDATETIME()
                                WHERE is_current = 1 AND city_code = %s
                                  AND node_id = %s AND row_hash <> %s""",
                            (cd, nid, rh))
                n_chg += max(cur.rowcount, 0)
                cols = list(vals.keys())
                if lat is not None and lon is not None:
                    cur.execute(
                        f"IF NOT EXISTS (SELECT 1 FROM silver.bus_stop "
                        f"WHERE is_current=1 AND city_code=%s AND node_id=%s) "
                        f"INSERT INTO silver.bus_stop ({', '.join(cols)}, geog, row_hash) "
                        f"VALUES ({', '.join(['%s']*len(cols))}, "
                        f"geography::Point(%s, %s, 4326), %s)",
                        (cd, nid) + tuple(vals[c] for c in cols) + (lat, lon, rh))
                else:
                    cur.execute(
                        f"IF NOT EXISTS (SELECT 1 FROM silver.bus_stop "
                        f"WHERE is_current=1 AND city_code=%s AND node_id=%s) "
                        f"INSERT INTO silver.bus_stop ({', '.join(cols)}, row_hash) "
                        f"VALUES ({', '.join(['%s']*len(cols))}, %s)",
                        (cd, nid) + tuple(vals[c] for c in cols) + (rh,))
                # ★ IF NOT EXISTS ... INSERT 는 안 넣었을 때 rowcount 가 -1 이다
                n_new += max(cur.rowcount, 0)
            conn.commit()
            if len(items) < args.rows:
                break
            page += 1
        print(f"  {nm}({cd})  수신 {got:6,}  누적신규 {n_new:7,}")

    cur.execute("SELECT COUNT(*) FROM silver.bus_stop WHERE is_current = 1")
    tot = cur.fetchone()[0]
    print(f"\n정류소 총 {tot:,}건  (호출 {calls:,} · 수신 {recv:,} · "
          f"신규 {n_new:,} · 변경 {n_chg:,} · 좌표없음 {no_xy:,})")
    _notify("버스정류소 적재 완료",
            [f"도시 {len(cs)}곳 · 호출 {calls:,}",
             f"정류소 총 {tot:,}건 (신규 {n_new:,})",
             f"좌표 없음 {no_xy:,}건"])
    conn.close()


if __name__ == "__main__":
    main()
