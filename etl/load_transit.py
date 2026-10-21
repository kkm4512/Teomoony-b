#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
load_transit - 버스정류장 / 지하철역을 파일에서 적재

  py load_transit.py --what bus      (data/bus_stop_*.csv)
  py load_transit.py --what subway   (data/subway_station_*.xlsx)
  py load_transit.py                 (둘 다)

출처 / 라이선스
  버스   : 국토교통부_전국 버스정류장 위치정보 (data.go.kr 15067528)
           CSV / EUC-KR / 227,065행 / 연 1회
  지하철 : 전국도시철도역사정보표준데이터 (data.go.kr 15013205, 국가철도공단)
           XLSX / 1,099행 / 47노선 / 연 1회 / 이용허락범위 제한 없음

★ 왜 API 가 아니라 파일인가
  · 버스: TAGO API(15096280) 의 도시 목록 138곳에 **서울이 없다**(실측).
    우리 단지는 전부 서울이라 API 로는 한 건도 못 붙인다.
    같은 국토부 **파일**에는 서울 16,980 승강장이 들어 있다.
  · 지하철: 역 좌표를 주는 살아있는 오픈API 가 사실상 없다 -
    포털 '지하철역 위경도' 오픈API 0건, 서울 열린데이터광장
    '서울시 역사마스터 정보' 는 **서비스 종료**.

★ 둘 다 연 1회 갱신이다. 파일이 오히려 맞다(정비구역 uq120 과 같은 모양).
"""
import argparse, csv, glob, hashlib, io, os, sys, time
import pymssql

from load_building import load_env

HERE = os.path.dirname(os.path.abspath(__file__))
ENV  = os.path.join(HERE, "..", ".env")
DATA = os.path.join(HERE, "data")


def _notify(title, lines):
    try:
        import notify
        ok, why = notify.send("[터무니] " + title + "\n" + "\n".join(lines))
        print(f"[알림] {'보냄' if ok else '안 보냄 - ' + str(why)}")
    except Exception as e:
        print(f"[알림] 실패 - {type(e).__name__}: {e}")


def newest(pattern):
    hits = sorted(glob.glob(os.path.join(DATA, pattern)))
    if not hits:
        sys.exit(f"파일이 없습니다: etl/data/{pattern}")
    return hits[-1]


def conn_db(env):
    return pymssql.connect(server=env.get("DB_HOST", "127.0.0.1"),
                           port=int(env.get("DB_PORT", 11433)),
                           user=env.get("DB_USER", "sa"),
                           password=env.get("DB_PASSWORD", ""),
                           database=env.get("DB_NAME", "Teomoony"),
                           charset="UTF-8", autocommit=False)


def bulk(cur, table, cols, keycols, rows, chunk=1000):
    """임시테이블에 한꺼번에 넣고 **한 번의 SQL 로** SCD2 를 처리한다.

    ★ 왜 바꿨나 (2026-10-19)
      처음엔 한 줄에 UPDATE 1 + IF NOT EXISTS INSERT 1, 즉 **2회 왕복**이었다.
      버스 227,065행 = 45만 회 왕복이라 실측 **20,000행에 7분** - 전체 80분.
      적재 자체보다 왕복이 비용이었다. 임시테이블 + 집합 연산이면 몇 분이다.
      (쿼리를 줄인 게 아니라 **왕복을 줄였다.** 상권에서 호출 133->2 로 줄인
       것과 같은 종류의 문제다 - 한 건씩 부르지 말 것.)

    rows: [(값들..., row_hash, lat, lon)] - cols 순서 + 뒤에 hash/lat/lon
    """
    tmp = "#stage"
    cur.execute(f"IF OBJECT_ID('tempdb..{tmp}') IS NOT NULL DROP TABLE {tmp}")
    # 본 테이블과 **같은 타입**으로 임시테이블을 만든다 - 타입을 손으로 적으면
    # 언젠가 어긋난다. 0건 SELECT 로 모양만 복사한다.
    cur.execute(f"SELECT TOP 0 {', '.join(cols)}, row_hash, "
                f"lat_s = CAST(NULL AS DECIMAL(11,8)), lon_s = CAST(NULL AS DECIMAL(12,8)) "
                f"INTO {tmp} FROM {table}")
    ph = ", ".join(["%s"] * (len(cols) + 3))
    ins = f"INSERT INTO {tmp} ({', '.join(cols)}, row_hash, lat_s, lon_s) VALUES ({ph})"
    for i in range(0, len(rows), chunk):
        cur.executemany(ins, rows[i:i + chunk])
    on = " AND ".join(f"s.{c} = b.{c}" for c in keycols)
    cur.execute(f"""UPDATE b SET is_current = 0, valid_to = SYSDATETIME()
                      FROM {table} b JOIN {tmp} s ON {on}
                     WHERE b.is_current = 1 AND b.row_hash <> s.row_hash""")
    chg = max(cur.rowcount, 0)
    ex = " AND ".join(f"b.{c} = s.{c}" for c in keycols)
    cur.execute(f"""INSERT INTO {table} ({', '.join(cols)}, geog, row_hash)
                    SELECT {', '.join('s.' + c for c in cols)},
                           CASE WHEN s.lat_s IS NOT NULL AND s.lon_s IS NOT NULL
                                THEN geography::Point(s.lat_s, s.lon_s, 4326) END,
                           s.row_hash
                      FROM {tmp} s
                     WHERE NOT EXISTS (SELECT 1 FROM {table} b
                                        WHERE b.is_current = 1 AND {ex})""")
    new = max(cur.rowcount, 0)
    cur.execute(f"DROP TABLE {tmp}")
    return new, chg


def rowhash(vals):
    return hashlib.sha256(
        "\x1f".join(str(vals[k]) for k in sorted(vals) if k != "collected_at")
        .encode("utf-8")).digest()


# 대한민국 범위. 이 밖이면 **쓰지 않는다.**
KR = (32.0, 39.7, 124.0, 132.2)   # lat_min, lat_max, lon_min, lon_max


def num(s):
    try:
        v = float(s)
    except Exception:
        return None
    return round(v, 8)


def xy(lat_s, lon_s):
    """좌표를 읽고 **한반도 밖이면 버린다.** (lat, lon, 사유) 를 준다.

    ★ 2026-10-19: 버스 CSV 에 **위경도가 뒤바뀐 6건**이 있었다
      (예: DJB3064513 한국농어촌공사 위도 127.2822 / 경도 36.4683 - 대전).
      그대로 넣었더니 SQL Server 가
      'Latitude values must be between -90 and 90' 로 **적재를 통째로 죽였다.**
    ★ 뒤바꿔 고치지 않는다. 명백해 보여도 그건 추측이고, 조용히 틀린 좌표는
      NULL 보다 나쁘다(정책 1장). 좌표만 비우고 **몇 건인지 말한다.**
      행 자체는 넣는다 - 이름과 번호는 멀쩡하다.
    """
    lat, lon = num(lat_s), num(lon_s)
    if lat is None or lon is None:
        return None, None, "없음"
    if not (KR[0] <= lat <= KR[1] and KR[2] <= lon <= KR[3]):
        return None, None, "범위밖"
    return lat, lon, None


def do_bus(cur, today):
    path = newest("bus_stop_*.csv")
    print(f"버스  {os.path.basename(path)}")
    # 받아올 때 UTF-8 로 바꿔 두었다. 원본은 EUC-KR 이다.
    with io.open(path, encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))
    need = ["정류장번호", "정류장명", "위도", "경도", "정보수집일",
            "모바일단축번호", "도시코드", "도시명", "관리도시명"]
    miss = [c for c in need if c not in (rows[0].keys() if rows else [])]
    if miss:
        sys.exit(f"컬럼이 바뀌었다: 없음 {miss} / 있는 것 {list(rows[0].keys())}")
    cols = ["stop_no", "stop_nm", "ars_no", "city_code", "city_nm",
            "mng_city_nm", "lat", "lon", "collect_date", "collected_at"]
    payload, no_xy, out_kr = [], 0, 0
    for r in rows:
        lat, lon, why = xy(r["위도"], r["경도"])
        if why == "없음":
            no_xy += 1
        elif why == "범위밖":
            out_kr += 1
        vals = dict(
            stop_no=r["정류장번호"].strip(),
            stop_nm=(r["정류장명"] or "").strip() or None,
            ars_no=(r["모바일단축번호"] or "").strip() or None,
            city_code=(r["도시코드"] or "").strip() or None,
            city_nm=(r["도시명"] or "").strip() or None,
            mng_city_nm=(r["관리도시명"] or "").strip() or None,
            lat=lat, lon=lon,
            collect_date=(r["정보수집일"] or "").strip() or None,
            collected_at=today)
        payload.append(tuple(vals[c] for c in cols) + (rowhash(vals), lat, lon))
    n_new, n_chg = bulk(cur, "silver.bus_stop", cols, ["stop_no"], payload)
    print(f"  읽음 {len(rows):,} · 신규 {n_new:,} · 변경 {n_chg:,} · 좌표없음 {no_xy:,}")
    if out_kr:
        print(f"  ※ 좌표가 한반도 밖이라 **비운** 행 {out_kr}건 "
              f"(위경도가 뒤바뀐 것으로 보임 - 고치지 않고 비웠습니다)")
    return len(rows), n_new, no_xy


def do_subway(cur, today):
    # ★ 원본은 XLSX 지만 **CSV 로 미리 바꿔서** data/ 에 넣는다.
    #   윈도우 쪽 파이썬에 openpyxl 이 없어서 2026-10-19 에 여기서 터졌다.
    #   파이프라인에 의존 하나를 더 다는 것보다, 받을 때 한 번 바꾸는 게 싸다
    #   (정비구역 uq120 을 ndjson 으로 미리 바꿔 둔 것과 같은 판단).
    #   변환법은 data/README.txt 에 적어 둔다. .xlsx 원본도 같이 둔다.
    path = newest("subway_station_*.csv")
    print(f"지하철 {os.path.basename(path)}")
    with io.open(path, encoding="utf-8", newline="") as f:
        rd = csv.reader(f)
        hdr = [h.strip() for h in next(rd)]
        want = ["역번호", "역사명", "노선번호", "노선명", "영문역사명", "한자역사명",
                "환승역구분", "환승노선번호", "환승노선명", "역위도", "역경도",
                "운영기관명", "역사도로명주소", "역사전화번호", "데이터기준일자"]
        miss = [c for c in want if c not in hdr]
        if miss:
            sys.exit(f"컬럼이 바뀌었다: 없음 {miss} / 있는 것 {hdr}")
        ix = {c: hdr.index(c) for c in want}
        raw = [r for r in rd if r and r[ix["역번호"]]]

    # ★ 완전중복(모든 칸이 같은 줄)을 지운다 - 주안역 경인선 1건(실측).
    #   몇 건 뺐는지 **반드시 말한다.** 조용히 줄이면 나중에 설명이 안 된다.
    seen, rows, dropped = set(), [], 0
    for r in raw:
        k = tuple("" if v is None else str(v) for v in r)
        if k in seen:
            dropped += 1
            continue
        seen.add(k)
        rows.append(r)
    if dropped:
        print(f"  ※ 모든 칸이 같은 줄 {dropped}건을 뺐습니다 (원본 {len(raw):,} -> {len(rows):,})")

    def g(r, c):
        v = r[ix[c]]
        return (str(v).strip() or None) if v is not None else None

    cols = ["line_cd", "sttn_cd", "line_nm", "sttn_nm", "sttn_nm_en", "sttn_nm_cn",
            "transfer_se", "transfer_line_cd", "transfer_line_nm", "lat", "lon",
            "oper_nm", "road_addr", "tel", "base_date", "collected_at"]
    payload, no_xy, seen2, dup2 = [], 0, set(), 0
    for r in rows:
        lat, lon, why = xy(r[ix["역위도"]], r[ix["역경도"]])
        if why:
            no_xy += 1
        vals = dict(
            line_cd=g(r, "노선번호") or "", sttn_cd=g(r, "역번호") or "",
            line_nm=g(r, "노선명") or "", sttn_nm=g(r, "역사명") or "",
            sttn_nm_en=g(r, "영문역사명"), sttn_nm_cn=g(r, "한자역사명"),
            transfer_se=g(r, "환승역구분"),
            transfer_line_cd=g(r, "환승노선번호"),
            transfer_line_nm=g(r, "환승노선명"),
            lat=lat, lon=lon,
            oper_nm=g(r, "운영기관명"), road_addr=g(r, "역사도로명주소"),
            tel=g(r, "역사전화번호"), base_date=g(r, "데이터기준일자"),
            collected_at=today)
        # ★ 임시테이블에 자연키가 겹치면 UPDATE/INSERT 가 애매해진다.
        #   좌표만 다른 '같은 역' 2줄(주안역)이 실제로 있다 - 먼저 온 줄을 남기고
        #   **몇 건 뺐는지 말한다.** 조용히 줄이지 않는다.
        k = (vals["line_cd"], vals["sttn_cd"], vals["line_nm"], vals["sttn_nm"])
        if k in seen2:
            dup2 += 1
            continue
        seen2.add(k)
        payload.append(tuple(vals[c] for c in cols) + (rowhash(vals), lat, lon))
    if dup2:
        print(f"  ※ 자연키가 같은 줄 {dup2}건을 뺐습니다 (먼저 온 줄을 남김)")
    n_new, n_chg = bulk(cur, "silver.subway_station", cols,
                        ["line_cd", "sttn_cd", "line_nm", "sttn_nm"], payload)
    print(f"  읽음 {len(payload):,} · 신규 {n_new:,} · 변경 {n_chg:,} · 좌표없음 {no_xy:,}")
    return len(payload), n_new, no_xy


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--what", choices=["bus", "subway", "both"], default="both")
    args = ap.parse_args()
    env = load_env(ENV)
    conn = conn_db(env); cur = conn.cursor()
    today = time.strftime("%Y%m%d")
    msg = []

    if args.what in ("subway", "both"):
        tot, new, nx = do_subway(cur, today); conn.commit()
        msg.append(f"지하철역 {tot:,} (신규 {new:,})")
    if args.what in ("bus", "both"):
        tot, new, nx = do_bus(cur, today); conn.commit()
        msg.append(f"버스정류장 {tot:,} (신규 {new:,})")

    cur.execute("""SELECT (SELECT COUNT(*) FROM silver.bus_stop WHERE is_current=1),
                          (SELECT COUNT(*) FROM silver.bus_stop
                            WHERE is_current=1 AND city_nm = N'서울특별시'),
                          (SELECT COUNT(*) FROM silver.subway_station WHERE is_current=1)""")
    b, bs, s = cur.fetchone()
    print(f"\n버스 {b:,} (서울 {bs:,}) · 지하철역 {s:,}")
    _notify("대중교통 적재 완료", msg + [f"서울 버스 {bs:,} · 지하철역 {s:,}"])
    conn.close()


if __name__ == "__main__":
    main()
