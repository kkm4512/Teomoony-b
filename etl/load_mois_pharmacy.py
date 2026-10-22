# -*- coding: utf-8 -*-
"""load_mois_pharmacy - 행정안전부 약국 인허가 → silver.mois_pharmacy  (2026-10-22, deploy/sql/307)
  py load_mois_pharmacy.py                 DB 로
  py load_mois_pharmacy.py --sql-out 파일  SQL 파일로(/api/_apply)
★ 개방자치단체코드로 받는다: 서울 25구(3000000 … 3240000) + 안양시(3830000). 한 쪽 100건 상한 · 쪽당 ~10초라 전국(7만)은 2시간 — 구별로 2.3만.
★ 좌표 EPSG:5174 → WGS84: pyproj 가 있으면 그것, 없으면 tm5174.py(같은 정의, pyproj 와 6cm 안 — 2026-10-22 대조).
"""
import argparse, io, json, os, sys, time, urllib.parse, urllib.request
HERE = os.path.dirname(os.path.abspath(__file__)); ENV = os.path.join(HERE, "..", ".env")
URL = "https://apis.data.go.kr/1741000/pharmacies/info"


def env():
    d = {}
    for line in io.open(ENV, encoding="utf-8-sig"):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1); d[k.strip()] = v.strip().strip('"')
    return d


CODES = [str(3000000 + i * 10000) for i in range(25)] + ["3830000"]


def get(key, page, code):
    q = urllib.parse.urlencode({"serviceKey": key, "pageNo": page, "numOfRows": 100, "returnType": "json", "cond[OPN_ATMY_GRP_CD::EQ]": code})
    for t in range(5):
        try:
            j = json.loads(urllib.request.urlopen(URL + "?" + q, timeout=90).read().decode("utf-8"))
            b = j["response"]["body"]; it = (b.get("items") or {}).get("item") or []
            return int(b.get("totalCount") or 0), ([it] if isinstance(it, dict) else it)
        except Exception as ex:
            if t == 4: raise RuntimeError(f"p{page}: {str(ex).replace(key, '***')[:120]}")
            time.sleep(3 * (t + 1))


def d10(v):
    v = (v or "").strip()
    if len(v) == 8 and v.isdigit(): return f"{v[:4]}-{v[4:6]}-{v[6:]}"
    return v[:10] or None


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--sql-out"); a = ap.parse_args()
    e = env(); key = e.get("DATA_GO_KR_KEY", "")
    try:
        from pyproj import Transformer
        _t = Transformer.from_crs("EPSG:5174", "EPSG:4326", always_xy=True); conv = _t.transform
    except Exception:
        sys.path.insert(0, HERE); from tm5174 import to_wgs84 as conv
    keep = []
    for code in CODES:
        tot, rows = get(key, 1, code); p = 1
        while len(rows) < tot:
            p += 1; _, more = get(key, p, code)
            if not more: break
            rows += more; time.sleep(0.1)
        if len(rows) != tot: sys.exit(f"{code}: 받은 {len(rows)} ≠ totalCount {tot} — 넣지 않음")
        keep += [x for x in rows if (x.get("LOTNO_ADDR") or x.get("ROAD_NM_ADDR") or "").startswith(("서울특별시 ", "경기도 안양시"))]
        print(f"  {code}: {tot:,}", flush=True)
    print(f"서울·안양 {len(keep):,}", flush=True)
    out = []
    for x in keep:
        try: X, Y = float(x.get("CRD_INFO_X") or ""), float(x.get("CRD_INFO_Y") or "")
        except Exception: X = Y = None
        lng = lat = None
        if X and Y:
            lng, lat = conv(X, Y)
            if not (33 < lat < 39 and 124 < lng < 132): lng = lat = None
        out.append(dict(관리번호=x.get("MNG_NO"), 이름=x.get("BPLC_NM") or None, 영업상태=x.get("SALS_STTS_NM") or None,
                        상세상태=x.get("DTL_SALS_STTS_NM") or None, 인허가일=d10(x.get("LCPMT_YMD")), 폐업일=d10(x.get("CLSBIZ_YMD")),
                        휴업시작=d10(x.get("TCBIZ_BGNG_YMD")), 휴업끝=d10(x.get("TCBIZ_END_YMD")), 인허가취소일=d10(x.get("LCPMT_RTRCN_YMD")),
                        지번주소=x.get("LOTNO_ADDR") or None, 도로명주소=x.get("ROAD_NM_ADDR") or None, 전화=x.get("TELNO") or None,
                        자치단체코드=x.get("OPN_ATMY_GRP_CD") or None, x_5174=X, y_5174=Y,
                        lat=round(lat, 7) if lat else None, lng=round(lng, 7) if lng else None, 원문갱신=x.get("DAT_UPDT_PNT") or None))
    cols = list(out[0].keys())
    q = lambda v: "NULL" if v is None else (repr(v) if isinstance(v, (int, float)) else "N'" + str(v).replace("'", "''") + "'")
    sql = ["SET NOCOUNT ON;\nGO\n"]
    for i in range(0, len(out), 300):
        vals = ",\n".join("(" + ",".join(q(r[c]) for c in cols) + ")" for r in out[i:i + 300])
        sql.append(f"MERGE silver.mois_pharmacy AS t USING (VALUES\n{vals}\n) AS s({', '.join(cols)}) ON t.관리번호 = s.관리번호\n"
                   f"WHEN MATCHED THEN UPDATE SET {', '.join(f't.{c}=s.{c}' for c in cols[1:])}, t.받은시각=SYSDATETIME(),\n"
                   f"  t.geog = CASE WHEN s.lat IS NOT NULL THEN geography::Point(s.lat, s.lng, 4326) END\n"
                   f"WHEN NOT MATCHED THEN INSERT ({', '.join(cols)}, geog) VALUES ({', '.join('s.' + c for c in cols)},\n"
                   f"  CASE WHEN s.lat IS NOT NULL THEN geography::Point(s.lat, s.lng, 4326) END);\nGO\n")
    if a.sql_out:
        io.open(a.sql_out, "w", encoding="utf-8").write("".join(sql)); print("SQL 파일:", a.sql_out); return
    import pymssql
    conn = pymssql.connect(server=e.get("DB_HOST", "127.0.0.1"), port=int(e.get("DB_PORT", 11433)), user=e.get("DB_USER", "sa"),
                           password=e.get("DB_PASSWORD", ""), database=e.get("DB_NAME", "Teomoony"), charset="UTF-8", autocommit=False)
    cur = conn.cursor()
    for st in sql[1:]: cur.execute(st.replace("\nGO\n", ""))
    conn.commit(); conn.close(); print("넣음", len(out))


if __name__ == "__main__":
    main()
