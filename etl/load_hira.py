# -*- coding: utf-8 -*-
"""load_hira - 심평원 병원정보서비스 · 약국정보서비스 목록 적재  2026-10-21

  py load_hira.py            서울 전체 + 경기 중 안양 (병원 · 약국)
  py load_hira.py --probe    받기만 하고 건수만 말한다

★ 출처: apis.data.go.kr/B551182 hospInfoServicev2/getHospBasisList · pharmacyInfoService/getParmacyBasisList (DATA_GO_KR_KEY)
★ 한 번에 1000행. totalCount 만큼 다 받았을 때만 '안 보인 기관' 을 is_current = 0 으로 돌린다 — 덜 받고 지우면 거짓말이 된다.
★ 경기는 시군구 이름(또는 주소)에 '안양' 이 든 것만 싣는다(우리 범위).
"""
import argparse, io, json, os, sys, time
import urllib.parse, urllib.request
import pymssql

HERE = os.path.dirname(os.path.abspath(__file__))
ENV  = os.path.join(HERE, "..", ".env")
B    = "https://apis.data.go.kr/B551182/"
OPS  = {"HOSP": "hospInfoServicev2/getHospBasisList", "PHARM": "pharmacyInfoService/getParmacyBasisList"}


def env():
    d = {}
    for line in io.open(ENV, encoding="utf-8-sig"):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1); d[k.strip()] = v.strip()
    return d


def pages(K, op, sido):
    out, page, total = [], 1, None
    while True:
        u = B + op + "?serviceKey=" + K + "&" + urllib.parse.urlencode(
            {"sidoCd": sido, "numOfRows": 1000, "pageNo": page, "_type": "json"})
        for a in range(3):
            try:
                with urllib.request.urlopen(u, timeout=60) as r:
                    j = json.loads(r.read().decode("utf-8")); break
            except Exception as e:
                if a == 2: raise RuntimeError(f"{op} {sido} page {page}: {str(e)[:120]}")
                time.sleep(2 * (a + 1))
        h = j.get("response", {}).get("header", {})
        if h.get("resultCode") != "00": raise RuntimeError(f"{op} {sido}: {h}")
        b = j["response"]["body"]; total = int(b.get("totalCount") or 0)
        it = (b.get("items") or {}).get("item") or []
        it = it if isinstance(it, list) else [it]
        out += it
        if len(out) >= total or not it: return out, total
        page += 1; time.sleep(0.2)


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--probe", action="store_true"); a = ap.parse_args()
    e = env(); key = e.get("DATA_GO_KR_KEY", "")
    if not key: sys.exit(".env 의 DATA_GO_KR_KEY 가 비어 있습니다")
    K = key if "%" in key else urllib.parse.quote(key)
    got = {}
    for g, op in OPS.items():
        s, ts = pages(K, op, "110000")
        k, tk = pages(K, op, "310000")
        ay = [x for x in k if "안양" in (x.get("sgguCdNm") or "") or "안양시" in (x.get("addr") or "")]
        got[g] = (s + ay, len(s) == ts and len(k) == tk)
        print(f"{g}: 서울 {len(s)}/{ts} · 경기 {len(k)}/{tk} 중 안양 {len(ay)}", flush=True)
    if a.probe: return

    conn = pymssql.connect(server=e.get("DB_HOST", "127.0.0.1"), port=int(e.get("DB_PORT", 11433)),
                           user=e.get("DB_USER", "sa"), password=e.get("DB_PASSWORD", ""),
                           database=e.get("DB_NAME", "Teomoony"), charset="UTF-8", autocommit=False)
    cur = conn.cursor()
    def i(v):
        try: return int(v)
        except Exception: return None
    def f(v):
        try: return float(v)
        except Exception: return None
    for g, (rows, 다받음) in got.items():
        cur.execute("CREATE TABLE #seen (ykiho VARCHAR(120) PRIMARY KEY)")
        for x in rows:
            y = x.get("ykiho")
            if not y: continue
            lng, lat = f(x.get("XPos")), f(x.get("YPos"))
            vals = (g, x.get("yadmNm"), str(x.get("clCd") or "").zfill(2) or None, x.get("clCdNm"), str(x.get("sidoCd") or ""),
                    str(x.get("sgguCd") or ""), x.get("sgguCdNm"), x.get("emdongNm"), x.get("addr"), x.get("telno"),
                    str(x.get("estbDd") or "")[:8] or None, i(x.get("drTotCnt")), i(x.get("mdeptSdrCnt")), i(x.get("detySdrCnt")),
                    i(x.get("cmdcSdrCnt")), lat, lng, json.dumps(x, ensure_ascii=False))
            cur.execute("""UPDATE silver.hira_inst SET 구분=%s, yadm_nm=%s, cl_cd=%s, cl_cd_nm=%s, sido_cd=%s, sggu_cd=%s, sggu_nm=%s,
                             emdong_nm=%s, addr=%s, telno=%s, estb_dd=%s, dr_tot=%s, mdept_sdr=%s, dety_sdr=%s, cmdc_sdr=%s, lat=%s, lng=%s,
                             raw_json=%s, is_current=1, 마지막본시각=SYSDATETIME(), 사라진시각=NULL WHERE ykiho=%s""", vals + (y,))
            if cur.rowcount == 0:
                cur.execute("""INSERT INTO silver.hira_inst (구분, yadm_nm, cl_cd, cl_cd_nm, sido_cd, sggu_cd, sggu_nm, emdong_nm, addr, telno,
                                 estb_dd, dr_tot, mdept_sdr, dety_sdr, cmdc_sdr, lat, lng, raw_json, ykiho)
                               VALUES (""" + ",".join(["%s"] * 19) + ")", vals + (y,))
            cur.execute("IF NOT EXISTS (SELECT 1 FROM #seen WHERE ykiho=%s) INSERT INTO #seen VALUES (%s)", (y, y))
        if 다받음:
            cur.execute("""UPDATE h SET is_current=0, 사라진시각=SYSDATETIME() FROM silver.hira_inst h
                            WHERE h.구분=%s AND h.is_current=1 AND NOT EXISTS (SELECT 1 FROM #seen s WHERE s.ykiho=h.ykiho)""", (g,))
            print(f"  {g}: 안 보인 기관 {cur.rowcount} → is_current 0", flush=True)
        else:
            print(f"  {g}: totalCount 만큼 못 받아서 '사라짐' 판정은 건너뜀", flush=True)
        cur.execute("DROP TABLE #seen")
        conn.commit()
    cur.execute("""UPDATE silver.hira_inst SET geog = geography::Point(lat, lng, 4326)
                    WHERE lat BETWEEN 33 AND 39 AND lng BETWEEN 124 AND 132
                      AND (geog IS NULL OR ABS(geog.Lat - lat) > 1e-9 OR ABS(geog.Long - lng) > 1e-9)""")
    conn.commit()
    cur.execute("""SELECT 구분, cl_cd_nm, COUNT(*), SUM(CASE WHEN geog IS NULL THEN 1 ELSE 0 END) FROM silver.hira_inst
                    WHERE is_current = 1 GROUP BY 구분, cl_cd_nm ORDER BY COUNT(*) DESC""")
    for r in cur.fetchall(): print(f"  {r[0]} {r[1]} {r[2]:,} (좌표없음 {r[3]})")
    conn.close()


if __name__ == "__main__":
    main()
