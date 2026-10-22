# -*- coding: utf-8 -*-
"""load_seoul_redev_plan - 서울플랜+ 정비사업 계획(용적률·건폐율·층수·공급세대) 적재  2026-10-22

  py load_seoul_redev_plan.py                  받아서 넣고 구역과 잇기(gold.usp_link_redev_plan)
  py load_seoul_redev_plan.py --sql-out 파일    DB 대신 SQL 파일로 쓴다(작업 줄이 막혔을 때 /api/_apply 로 넣는다)

★ 키 = .env SEOUL_OPENAPI_KEY (환경변수가 있으면 그걸 쓴다). 키는 화면·로그에 찍지 않는다.
★ 원문 0 은 '안 적음' → NULL. 위치('공릉동 254 일대')에서 동 · 산 · 본번 · 부번만 뗀다. 못 떼면 비운다(추측 안 함).
"""
import argparse, io, json, os, re, sys, time, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ENV  = os.path.join(HERE, "..", ".env")
SVC  = [("NMTN", "vnBsnsNmtn"), ("RRGN", "vnBsnsRrgnPrmt"), ("SMAL", "vnBsnsSmalNmtn")]
LOC  = re.compile(r"([가-힣0-9]+?(?:동\d*가|\d*동|\d*가|리))\s*(산\s*)?(\d+)(?:\s*-\s*(\d+))?")


def env():
    d = {}
    try:
        for line in io.open(ENV, encoding="utf-8-sig"):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1); d[k.strip()] = v.strip()
    except FileNotFoundError:
        pass
    return d


def _call(key, svc, s, e):
    u = f"http://openapi.seoul.go.kr:8088/{key}/json/{svc}/{s}/{e}/"
    for t in range(3):
        try:
            with urllib.request.urlopen(u, timeout=60) as r:
                return json.loads(r.read().decode("utf-8")).get(svc) or {}
        except Exception as ex:
            if t == 2: raise RuntimeError(f"{svc} {s}-{e}: {type(ex).__name__}")
            time.sleep(2 * (t + 1))


빠진 = {}   # 서비스 → 서버 오류로 못 받은 줄 번호(그 한 줄만 받아도 ERROR-500 인 것)


def rows(key, svc):
    """★ 2026-10-22: vnBsnsRrgnPrmt 는 범위를 크게 잡으면 ERROR-500 을 낸다(1~1 은 됨) — 어떤 줄 하나가 서버를 넘어뜨린다.
       오류가 나면 범위를 반으로 쪼개 다시 부르고, **한 줄짜리도 안 되면 그 줄만 빼고 센다**(조용히 버리지 않는다)."""
    v = _call(key, svc, 1, 1)
    if (v.get("RESULT") or {}).get("CODE") != "INFO-000": raise RuntimeError(f"{svc}: {json.dumps(v, ensure_ascii=False)[:160]}")
    tot = int(v.get("list_total_count") or 0); out = []
    def 받기(s, e):
        v = _call(key, svc, s, e)
        if (v.get("RESULT") or {}).get("CODE") == "INFO-000":
            out.extend(v.get("row") or []); return
        if s == e: 빠진.setdefault(svc, []).append(s); return
        m = (s + e) // 2; 받기(s, m); 받기(m + 1, e)
    for s in range(1, tot + 1, 1000):
        받기(s, min(s + 999, tot)); time.sleep(0.2)
    if len(out) + len(빠진.get(svc, [])) != tot: raise RuntimeError(f"{svc}: {len(out)} + 빠짐 {len(빠진.get(svc, []))} ≠ {tot}")
    return out


def 숫(v):
    try:
        f = float(str(v).replace(",", ""))
        return None if f == 0 else f            # 원문 0 = 안 적음
    except Exception:
        return None


def 날(v):
    s = str(v or "").strip()
    return s[:10] if re.match(r"^\d{4}-\d{2}-\d{2}", s) else None


def 조각(addr):
    m = LOC.search(addr or "")
    if not m: return None, None, None, None
    return m.group(1), ("1" if m.group(2) else "0"), m.group(3), (m.group(4) or "0")


def 한줄(kind, x):
    # ★ 글자 칸은 글자로 — 원문이 층수를 0.0(숫자)로 주는 줄이 섞여 SQL VALUES 가 숫자/글자로 갈렸다(2026-10-22)
    x = {k: (None if v is None or (isinstance(v, float) and k in ("FLOOR", "PURPOSE", "SPFC_PREV", "SPFC_AFTER")) and not v
             else (str(v) if k in ("FLOOR", "PURPOSE", "SPFC_PREV", "SPFC_AFTER", "SPCFC_NM", "RGN_CODE_NM", "BSNS_NAME", "BSNS_ADDR",
                                   "CLASSIFY_G", "CLASSIFY_G_NM", "CLASSIFY_L", "CLASSIFY_L_NM", "PROPEL_CD", "PROPEL_CD_NM", "CLEANUP_BSNS_URL", "SITE_CODE")
                   and not isinstance(v, str) else v)) for k, v in x.items()}
    동, 산, 본, 부 = 조각(x.get("BSNS_ADDR"))
    정 = lambda v: (int(round(v)) if v is not None else None)
    return dict(seq=int(float(x["BASIC_INFO_SEQ"])), 자료=kind, 대분류코드=x.get("CLASSIFY_G"), 대분류=x.get("CLASSIFY_G_NM"),
                소분류코드=x.get("CLASSIFY_L"), 소분류=x.get("CLASSIFY_L_NM"), sgg=(x.get("SITE_CODE") or "")[:5] or None,
                사업명=x.get("BSNS_NAME"), 위치=x.get("BSNS_ADDR"), 사업면적=숫(x.get("BSNS_AREA")),
                용도지역_전=x.get("SPFC_PREV") or None, 용도지역_후=x.get("SPFC_AFTER") or None, 권역=x.get("RGN_CODE_NM") or None,
                추진단계코드=x.get("PROPEL_CD") or None, 추진단계=x.get("PROPEL_CD_NM") or None, 추진일=날(x.get("PROPEL_DT")),
                지정일=날(x.get("DSGN_DT")), 지구명=x.get("SPCFC_NM") or None, 연면적=숫(x.get("AREA")), 용적률=숫(x.get("FLAR_RT")),
                건폐율=숫(x.get("BLDGLND_RT")), 층수=(x.get("FLOOR") or None), 높이m=숫(x.get("HEIGHT")), 용도=x.get("PURPOSE") or None,
                공급세대=정(숫(x.get("SUPLY_HSHLD"))), 분양세대=정(숫(x.get("PARCEL"))), 임대세대=정(숫(x.get("RENTAL"))),
                임대비율=숫(x.get("RENTAL_RT")), 홈페이지=x.get("CLEANUP_BSNS_URL") or None,
                위치_동=동, 위치_산=산, 위치_본번=본, 위치_부번=부, raw=json.dumps(x, ensure_ascii=False))


COLS = ["basic_info_seq", "자료", "대분류코드", "대분류", "소분류코드", "소분류", "sgg_cd", "사업명", "위치", "사업면적", "용도지역_전",
        "용도지역_후", "권역", "추진단계코드", "추진단계", "추진일", "지정일", "지구명", "연면적", "용적률", "건폐율", "층수", "높이m", "용도",
        "공급세대", "분양세대", "임대세대", "임대비율", "홈페이지", "위치_동", "위치_산", "위치_본번", "위치_부번", "raw_json"]
KEYS = ["seq", "자료", "대분류코드", "대분류", "소분류코드", "소분류", "sgg", "사업명", "위치", "사업면적", "용도지역_전", "용도지역_후", "권역",
        "추진단계코드", "추진단계", "추진일", "지정일", "지구명", "연면적", "용적률", "건폐율", "층수", "높이m", "용도", "공급세대", "분양세대",
        "임대세대", "임대비율", "홈페이지", "위치_동", "위치_산", "위치_본번", "위치_부번", "raw"]


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--sql-out"); a = ap.parse_args()
    key = os.environ.get("SEOUL_OPENAPI_KEY") or env().get("SEOUL_OPENAPI_KEY", "")
    if not key: sys.exit(".env 에 SEOUL_OPENAPI_KEY 가 없습니다")
    allr = []
    for kind, svc in SVC:
        rs = rows(key, svc); allr += [한줄(kind, x) for x in rs]
        print(f"{kind} {svc}: {len(rs):,}" + (f" · 서버 오류로 못 받은 줄 {len(빠진[svc])}개: {빠진[svc][:20]}" if 빠진.get(svc) else ""), flush=True)
    seqs = [r["seq"] for r in allr]
    if len(seqs) != len(set(seqs)): sys.exit("BASIC_INFO_SEQ 가 자료끼리 겹칩니다 — 기본키를 다시 정해야 합니다")
    print(f"위치에서 동·지번을 뗀 것 {sum(1 for r in allr if r['위치_동']):,} / {len(allr):,}", flush=True)

    upd = ", ".join(f"{c}=%s" for c in COLS[1:])
    if a.sql_out:
        q = lambda v: "NULL" if v is None else (str(v) if isinstance(v, (int, float)) else "N'" + str(v).replace("'", "''") + "'")
        with io.open(a.sql_out, "w", encoding="utf-8") as f:
            f.write("/* load_seoul_redev_plan.py --sql-out 로 만든 파일 (301) */\nSET NOCOUNT ON;\n")
            for i in range(0, len(allr), 200):
                vals = ",\n".join("(" + ",".join(q(r[k]) for k in KEYS) + ")" for r in allr[i:i + 200])
                f.write(f"MERGE silver.seoul_redev_plan AS t USING (VALUES\n{vals}\n) AS s({', '.join(COLS)}) ON t.basic_info_seq = s.basic_info_seq\n"
                        f"WHEN MATCHED THEN UPDATE SET {', '.join(f't.{c}=s.{c}' for c in COLS[1:])}, t.loaded_at=SYSDATETIME()\n"
                        f"WHEN NOT MATCHED THEN INSERT ({', '.join(COLS)}) VALUES ({', '.join('s.' + c for c in COLS)});\nGO\n")
            f.write("EXEC gold.usp_link_redev_plan;\nGO\n")
        print(f"SQL 파일: {a.sql_out}"); return

    import pymssql
    e = env()
    conn = pymssql.connect(server=e.get("DB_HOST", "127.0.0.1"), port=int(e.get("DB_PORT", 11433)),
                           user=e.get("DB_USER", "sa"), password=e.get("DB_PASSWORD", ""),
                           database=e.get("DB_NAME", "Teomoony"), charset="UTF-8", autocommit=False)
    cur = conn.cursor()
    for r in allr:
        v = tuple(r[k] for k in KEYS)
        cur.execute(f"UPDATE silver.seoul_redev_plan SET {upd}, loaded_at=SYSDATETIME() WHERE basic_info_seq=%s", v[1:] + (v[0],))
        if cur.rowcount == 0:
            cur.execute(f"INSERT INTO silver.seoul_redev_plan ({', '.join(COLS)}) VALUES ({', '.join(['%s'] * len(COLS))})", v)
    conn.commit()
    cur.execute("EXEC gold.usp_link_redev_plan"); print("이음:", cur.fetchone()); conn.commit(); conn.close()


if __name__ == "__main__":
    main()
