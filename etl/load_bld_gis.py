#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""load_bld_gis - GIS건물통합정보(VWorld NED getBldgisSpceWFS) → silver.bld_gis  (2026-10-24, deploy/sql/349)

  py load_bld_gis.py                         적재 대상 시군구 전부
  py load_bld_gis.py --sgg 11680 --rps 2     한 구만, 초당 2

★ 사장님 "위반건축물 데이터도 주나? 웹사이트에 표시하면 좋긴해" — 위반 표시(violt_bild)가 있는 공식 경로가 이것뿐이다.
★ 시군구 필지 경계상자를 조각(--tile 도)으로 썰어 bbox WFS 로 받는다. 한 번에 1,000개가 차면 넷으로 다시 썬다(빠뜨리지 않게).
  조각 하나라도 끝내 실패하면 그 시군구를 '다 받음' 으로 적지 않는다(실패조각 > 0).
★ 속성 전부를 그대로 둔다(attrs_json). 바뀐 건물은 SCD2 새 버전 — 위반 지정 · 해제가 이력으로 남는다. 못 본 건물을 닫지는 않는다.
★ VWorld NED 는 초당 요청 수로 막는다 — 토지특성 적재와 같은 키를 쓰므로 같이 돌 때는 --rps 를 낮게.
★ 키는 화면 · 로그에 안 찍는다.
"""
import argparse, hashlib, json, os, sys, time, threading
from concurrent.futures import ThreadPoolExecutor, as_completed
import requests, pymssql
from _rate import 조절기
from _targets import 대상시군구

HERE = os.path.dirname(os.path.abspath(__file__))
URL = "https://api.vworld.kr/ned/wfs/getBldgisSpceWFS"
조절 = 조절기()
_tl = threading.local()


def env():
    d = {}
    for ln in open(os.path.join(HERE, "..", ".env"), encoding="utf-8"):
        ln = ln.strip()
        if ln and not ln.startswith("#") and "=" in ln:
            k, v = ln.split("=", 1); d[k.strip()] = v.strip().strip('"').strip("'")
    return d


def 세션():
    if not hasattr(_tl, "s"): _tl.s = requests.Session()
    return _tl.s


def 받기(key, dom, x0, y0, x1, y1, retries=5):
    """조각 하나. 돌려주는 것: features 목록 또는 None(실패 — 빈 것과 다르다)."""
    p = {"key": key, "domain": dom, "typename": "dt_d010", "bbox": f"{y0},{x0},{y1},{x1},EPSG:4326",
         "maxFeatures": 1000, "resultType": "results", "srsName": "EPSG:4326", "output": "application/json"}
    for a in range(retries):
        조절.기다림()
        try:
            r = 세션().get(URL, params=p, timeout=60)
            if r.status_code == 200 and r.text.lstrip().startswith("{"):
                조절.성공()
                return r.json().get("features") or []
            if r.status_code == 200 and "INCORRECT_KEY" in r.text.upper():
                raise SystemExit("★ VWorld 키/도메인 문제 — .env VWORLD_DOMAIN 확인")
            조절.실패()
        except SystemExit:
            raise
        except Exception:
            조절.실패()
        time.sleep(1.5 * (a + 1))
    return None


def 조각받기(key, dom, box, 깊이=0):
    """1,000개가 차면 넷으로 나눠 다시. (features, 실패조각수, 요청수)"""
    fs = 받기(key, dom, *box)
    if fs is None: return [], 1, 1
    if len(fs) < 1000 or 깊이 >= 6: return fs, 0, 1
    x0, y0, x1, y1 = box; mx, my = (x0 + x1) / 2, (y0 + y1) / 2
    out, 실패, 요청 = [], 0, 1
    for b in ((x0, y0, mx, my), (mx, y0, x1, my), (x0, my, mx, y1), (mx, my, x1, y1)):
        f, e, q = 조각받기(key, dom, b, 깊이 + 1); out += f; 실패 += e; 요청 += q
    return out, 실패, 요청


def 숫(v, t=float):
    try: return None if v in (None, "") else t(v)
    except Exception: return None


def 줄(pr):
    attrs = {k: v for k, v in pr.items()}
    h = hashlib.sha256(json.dumps({k: v for k, v in attrs.items() if k not in ("last_updt_dt", "src_objectid")},
                                  ensure_ascii=False, sort_keys=True).encode("utf-8")).digest()
    s = lambda k, n=None: (None if pr.get(k) in (None, "") else str(pr.get(k))[:n] if n else str(pr.get(k)))
    pnu = s("pnu"); pnu = pnu if pnu and len(pnu) == 19 else None
    return (s("gis_idntfc_no", 40), pnu, s("src_signgu_code", 5), s("buld_idntfc_no", 30), s("refrn_systm_cntc_no", 40),
            s("regstr_se_code", 4), s("buld_prpos_code", 10), s("buld_nm", 200), s("dong_nm", 200), s("use_confm_de", 10),
            숫(pr.get("totar")), 숫(pr.get("ground_floor_co"), int), 숫(pr.get("undgrnd_floor_co"), int),
            s("violt_bild", 1), s("data_creat_change_de", 10), s("last_updt_dt", 20),
            json.dumps(attrs, ensure_ascii=False, sort_keys=True), h)


COLS = ("gis_idntfc_no, pnu, sgg_cd, buld_idntfc_no, refrn_systm_cntc_no, regstr_se_code, buld_prpos_code, buld_nm, dong_nm, "
        "use_confm_de, totar, ground_floor_co, undgrnd_floor_co, violt_bild, data_creat_change_de, last_updt_dt, attrs_json, row_hash")


def 쓰기(conn, rows):
    """#b 에 담고 집합으로 SCD2: 같은 해시 = 마지막본시각만 · 다른 해시 = 옛 줄 닫고 새 줄 · 없던 것 = 새 줄"""
    cur = conn.cursor()
    cur.execute(f"""IF OBJECT_ID('tempdb..#b') IS NOT NULL DROP TABLE #b;
        SELECT TOP 0 {COLS} INTO #b FROM silver.bld_gis;""")
    ph = "(" + ",".join(["%s"] * 18) + ")"
    for i in range(0, len(rows), 150):
        ch = rows[i:i + 150]
        cur.execute(f"INSERT #b ({COLS}) VALUES " + ",".join([ph] * len(ch)), tuple(v for r in ch for v in r))
    cur.execute("""
        UPDATE s SET 마지막본시각 = SYSDATETIME() FROM silver.bld_gis s JOIN #b b ON b.gis_idntfc_no = s.gis_idntfc_no
         WHERE s.is_current = 1 AND s.row_hash = b.row_hash;
        DECLARE @바뀜 INT;
        UPDATE s SET is_current = 0, valid_to = SYSDATETIME() FROM silver.bld_gis s JOIN #b b ON b.gis_idntfc_no = s.gis_idntfc_no
         WHERE s.is_current = 1 AND s.row_hash <> b.row_hash;
        SET @바뀜 = @@ROWCOUNT;
        INSERT silver.bld_gis (""" + COLS + """)
        SELECT """ + COLS + """ FROM #b b WHERE NOT EXISTS (SELECT 1 FROM silver.bld_gis s WHERE s.gis_idntfc_no = b.gis_idntfc_no AND s.is_current = 1);
        SELECT 새 = @@ROWCOUNT, 바뀜 = @바뀜;""")
    새, 바뀜 = cur.fetchone(); conn.commit()
    return 새, 바뀜


def main():
    global 조절
    ap = argparse.ArgumentParser()
    ap.add_argument("--sgg", nargs="*"); ap.add_argument("--tile", type=float, default=0.01)
    ap.add_argument("--rps", type=float, default=2); ap.add_argument("--max-rps", type=float, default=4); ap.add_argument("--rest", type=float, default=30)
    ap.add_argument("--workers", type=int, default=6); ap.add_argument("--skip-done", action="store_true")
    a = ap.parse_args()
    조절 = 조절기(a.rps, a.max_rps, a.rest)
    e = env(); key = e.get("VWORLD_KEY", ""); dom = (e.get("VWORLD_DOMAIN") or "teomoony.com").strip()
    if not key: sys.exit(".env 의 VWORLD_KEY 가 비어 있습니다")
    conn = pymssql.connect(server=e.get("DB_HOST", "127.0.0.1"), port=int(e.get("DB_PORT", 11433)), user=e.get("DB_USER", "sa"),
                           password=e.get("DB_PASSWORD", ""), database=e.get("DB_NAME", "Teomoony"), charset="UTF-8", autocommit=False)
    cur = conn.cursor()
    sggs = a.sgg or 대상시군구(cur=cur)
    done = set()
    if a.skip_done:
        cur.execute("SELECT sgg_cd FROM silver.bld_gis_done WHERE 실패조각 = 0"); done = {r[0] for r in cur.fetchall()}
    cur.execute("""SELECT LEFT(pnu,5), MIN(bbox_minx), MIN(bbox_miny), MAX(bbox_maxx), MAX(bbox_maxy) FROM silver.cadastral_parcel
                    WHERE is_current = 1 GROUP BY LEFT(pnu,5)""")
    상자 = {r[0]: [float(x) for x in r[1:]] for r in cur.fetchall()}
    print(f"시군구 {len(sggs)} · 조각 {a.tile}도 · 초당 {a.rps}~{a.max_rps} · 스레드 {a.workers}", flush=True)
    t0 = time.monotonic(); 합 = [0, 0, 0]
    for sgg in sggs:
        if sgg in done: continue
        if sgg not in 상자:
            print(f"  {sgg}: 필지 경계가 없어 건너뜀(지적도 먼저)", flush=True); continue
        x0, y0, x1, y1 = 상자[sgg]; pad = 0.0005
        boxes = []
        x = x0 - pad
        while x < x1 + pad:
            y = y0 - pad
            while y < y1 + pad:
                boxes.append((round(x, 6), round(y, 6), round(min(x + a.tile, x1 + pad), 6), round(min(y + a.tile, y1 + pad), 6))); y += a.tile
            x += a.tile
        모음, 실패, 요청, 수신 = {}, 0, 0, 0
        with ThreadPoolExecutor(a.workers) as ex:
            for fut in as_completed([ex.submit(조각받기, key, dom, b) for b in boxes]):
                fs, f, q = fut.result(); 실패 += f; 요청 += q; 수신 += len(fs)
                for ft in fs:
                    pr = ft.get("properties") or {}
                    if str(pr.get("src_signgu_code") or "")[:5] != sgg and str(pr.get("pnu") or "")[:5] != sgg: continue
                    g = pr.get("gis_idntfc_no")
                    if g: 모음[str(g)] = pr
        rows = [줄(pr) for pr in 모음.values()]
        새 = 바뀜 = 0
        for i in range(0, len(rows), 3000):
            n, c = 쓰기(conn, rows[i:i + 3000]); 새 += n; 바뀜 += c
        cur.execute("""MERGE silver.bld_gis_done t USING (SELECT %s sgg_cd) s ON t.sgg_cd = s.sgg_cd
                       WHEN MATCHED THEN UPDATE SET 조각 = %s, 수신 = %s, 건물 = %s, 실패조각 = %s, 받은시각 = SYSDATETIME()
                       WHEN NOT MATCHED THEN INSERT (sgg_cd, 조각, 수신, 건물, 실패조각) VALUES (%s, %s, %s, %s, %s);""",
                    (sgg, 요청, 수신, len(rows), 실패, sgg, 요청, 수신, len(rows), 실패))
        conn.commit()
        cur.execute("EXEC gold.usp_refresh_bld_violation @sgg = %s", (sgg,)); 이음 = cur.fetchone()[0]; conn.commit()
        위반 = sum(1 for r in rows if r[13] == "Y")
        합[0] += len(rows); 합[1] += 위반; 합[2] += 실패
        print(f"  [{time.strftime('%H:%M:%S')}] {sgg} 요청 {요청:,} · 건물 {len(rows):,} (새 {새:,} · 바뀜 {바뀜:,}) · 위반 {위반:,} · 대장 이음 {이음:,}"
              + (f" · ★ 실패 조각 {실패}" if 실패 else "") + f" · 초당 {조절.rps:.0f} · 막힘 {조절.쉼횟수}번 ({(time.monotonic() - t0) / 60:.1f}분)", flush=True)
    print(f"\n건물 {합[0]:,} · 위반 {합[1]:,} · 실패 조각 {합[2]} (다시: --skip-done)")
    conn.close()
    if 합[2]: sys.exit(2)


if __name__ == "__main__":
    main()
