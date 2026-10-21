#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
load_bus_route - 서울 버스 노선과 **노선별 경유 정류장**을 적재

  py load_bus_route.py              (우선순위대로, 하루 한도까지)
  py load_bus_route.py --max 300    (이번 실행에서 받을 노선 수 제한)

출처: 서울특별시_노선정보조회 서비스 (data.go.kr 15000193)
      http://ws.bus.go.kr/api/rest/busRouteInfo/...
      **공공누리 1유형(출처표시)** · 개발계정 1,000건/일

★ 왜 노선 기준인가
  '이 정류장에 몇 번이 서나' 를 정류장마다 물으면 서울 13,010 승강장 ×1 이다.
  노선마다 물으면 **1,352회**로 전부 덮인다.
  (상권에서 배운 것과 같다 - 반경마다 부르지 말고 영역 한 번에: 133회 → 2회)

★ 하루 한도를 넘으므로 **이어받기**로 만든다
  이미 `bus_route_station` 에 있는 노선은 건너뛴다.
  한도/에러를 만나면 **받은 데까지 저장하고 깨끗이 멈춘다.** 다음 날 이어진다.

★ 우선순위 (routeType 은 노선명으로 실측해서 정했다)
  3 간선 · 4 지선 · 2 마을  ← 동네 버스. 제일 먼저.
  6 광역 · 15 심야 · 5 순환 · 1 공항 · 14 한강 · 10 관광
  8 경기 · 7 인천           ← 서울을 '지나가는' 노선. 마지막.
"""
import argparse, json, os, sys, time
import requests
import pymssql

from load_building import load_env

HERE = os.path.dirname(os.path.abspath(__file__))
ENV  = os.path.join(HERE, "..", ".env")
BASE = "http://ws.bus.go.kr/api/rest/busRouteInfo"
PRIO = ["3", "4", "2", "6", "15", "5", "1", "14", "10", "8", "7"]


def _notify(title, lines):
    try:
        import notify
        ok, why = notify.send("[터무니] " + title + "\n" + "\n".join(lines))
        print(f"[알림] {'보냄' if ok else '안 보냄 - ' + str(why)}")
    except Exception as e:
        print(f"[알림] 실패 - {type(e).__name__}: {e}")


class Stop(Exception):
    """더 못 받는 상황. 받은 데까지 저장하고 멈춘다."""


def call(op, key, params, retries=3):
    p = dict(params); p["serviceKey"] = key; p["resultType"] = "json"
    last = None
    for t in range(retries):
        try:
            r = requests.get(f"{BASE}/{op}", params=p, timeout=60)
            j = r.json()
        except Exception as e:
            last = e
            time.sleep(2 * (t + 1))
            continue
        h = j.get("msgHeader") or {}
        cd = str(h.get("headerCd", ""))
        if cd != "0":
            # ★ 무엇이 한도 초과인지 미리 알 수 없다. 0 이 아니면 **멈춘다.**
            #   조용히 0건으로 넘기지 않는다.
            raise Stop(f"{op} 거절 headerCd={cd} · {h.get('headerMsg')}")
        return (j.get("msgBody") or {}).get("itemList") or []
    raise Stop(f"{op} 호출 실패: {last}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max", type=int, default=950,
                    help="이번 실행에서 받을 노선 수 (하루 한도 1,000 보다 조금 적게)")
    args = ap.parse_args()

    env = load_env(ENV)
    key = env.get("DATA_GO_KR_KEY", "").strip()
    conn = pymssql.connect(server=env.get("DB_HOST", "127.0.0.1"),
                           port=int(env.get("DB_PORT", 11433)),
                           user=env.get("DB_USER", "sa"),
                           password=env.get("DB_PASSWORD", ""),
                           database=env.get("DB_NAME", "Teomoony"),
                           charset="UTF-8", autocommit=False)
    cur = conn.cursor()
    today = time.strftime("%Y%m%d")

    routes = call("getBusRouteList", key, {})
    print(f"노선 {len(routes):,}개")

    for r in routes:
        cur.execute("""MERGE silver.bus_route AS t
                       USING (SELECT %s AS route_id) AS s ON t.route_id = s.route_id
                       WHEN MATCHED THEN UPDATE SET route_nm=%s, route_abrv=%s,
                            route_type=%s, st_station_nm=%s, ed_station_nm=%s,
                            term=%s, corp_nm=%s, first_bus_tm=%s, last_bus_tm=%s,
                            collected_at=%s
                       WHEN NOT MATCHED THEN INSERT (route_id, route_nm, route_abrv,
                            route_type, st_station_nm, ed_station_nm, term, corp_nm,
                            first_bus_tm, last_bus_tm, collected_at)
                            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s);""",
                    (r["busRouteId"],
                     r.get("busRouteNm"), r.get("busRouteAbrv"), r.get("routeType"),
                     r.get("stStationNm"), r.get("edStationNm"), r.get("term"),
                     r.get("corpNm"), r.get("firstBusTm"), r.get("lastBusTm"), today,
                     r["busRouteId"],
                     r.get("busRouteNm"), r.get("busRouteAbrv"), r.get("routeType"),
                     r.get("stStationNm"), r.get("edStationNm"), r.get("term"),
                     r.get("corpNm"), r.get("firstBusTm"), r.get("lastBusTm"), today))
    conn.commit()
    print("  노선 마스터 저장")

    cur.execute("SELECT DISTINCT route_id FROM silver.bus_route_station")
    done = set(x[0] for x in cur.fetchall())
    print(f"  이미 받은 노선 {len(done):,}개 — 건너뜁니다")

    todo = [r for r in routes if r["busRouteId"] not in done]
    todo.sort(key=lambda r: (PRIO.index(r.get("routeType")) if r.get("routeType") in PRIO else 99,
                             r.get("busRouteNm") or ""))
    todo = todo[:args.max]
    print(f"  이번에 받을 노선 {len(todo):,}개 (남은 전체 {len(routes)-len(done):,})")

    calls = n_st = 0
    stopped = None
    for i, r in enumerate(todo, 1):
        rid = r["busRouteId"]
        try:
            items = call("getStaionByRoute", key, {"busRouteId": rid})
        except Stop as e:
            stopped = str(e)
            break
        calls += 1
        rows = []
        seen = set()
        for x in items:
            try:
                seq = int(x.get("seq"))
            except Exception:
                continue
            if seq in seen:       # 같은 순번이 두 번 오면 앞의 것만 (PK 충돌 방지)
                continue
            seen.add(seq)
            ars = (x.get("arsId") or "").strip()
            def f(v):
                try: return round(float(v), 8)
                except Exception: return None
            rows.append((rid, seq, (x.get("station") or "").strip() or None,
                         ars or None, (x.get("stationNm") or "").strip() or None,
                         (x.get("direction") or "").strip() or None,
                         f(x.get("gpsX")), f(x.get("gpsY")), today))
        if rows:
            cur.execute("DELETE FROM silver.bus_route_station WHERE route_id = %s", (rid,))
            cur.executemany(
                "INSERT INTO silver.bus_route_station (route_id, seq, station_id, "
                "ars_no, station_nm, direction, lon, lat, collected_at) "
                "VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)", rows)
            n_st += len(rows)
        if i % 50 == 0:
            conn.commit()
            print(f"    {i:,}/{len(todo):,}  정류장 누적 {n_st:,}")
    conn.commit()

    cur.execute("""SELECT (SELECT COUNT(*) FROM silver.bus_route),
                          (SELECT COUNT(DISTINCT route_id) FROM silver.bus_route_station),
                          (SELECT COUNT(*) FROM silver.bus_route_station)""")
    a, b, c = cur.fetchone()
    print(f"\n노선 {a:,} · 정류장 받은 노선 {b:,} · 노선x정류장 {c:,}  (이번 호출 {calls:,})")
    if stopped:
        print(f"★ 멈춤: {stopped}")
        print("  받은 데까지 저장했습니다. 내일 같은 작업을 다시 부르면 이어집니다.")
    msg = [f"노선 {b:,}/{a:,} · 노선x정류장 {c:,}", f"이번 호출 {calls:,}"]
    if stopped:
        msg.append("한도/에러로 멈춤 - 내일 이어받기")
    _notify("버스 경유노선 적재", msg)
    conn.close()


if __name__ == "__main__":
    main()
