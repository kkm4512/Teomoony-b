# -*- coding: utf-8 -*-
"""load_applyhome_cmpet - 청약홈 경쟁률 · 당첨가점 적재  2026-10-22

  py load_applyhome_cmpet.py           우리가 받은 공고(silver.applyhome_pblanc)의 경쟁률·가점만
  py load_applyhome_cmpet.py --probe   받기만, 건수

★ 목록 전체를 받아(종류마다 수천~5만 행, 1000행/쪽) **우리 공고에 있는 관리번호만** 넣는다 — 공고마다 따로 부르면 수천 번이다.
★ 다 받았을 때만 넣는다(받은 수 = totalCount).
"""
import argparse, io, json, os, re, sys, time
import urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ENV  = os.path.join(HERE, "..", ".env")
B    = "https://api.odcloud.kr/api/ApplyhomeInfoCmpetRtSvc/v1/"
CMPET = [("APT", "getAPTLttotPblancCmpet"), ("URBTY", "getUrbtyOfctlLttotPblancCmpet"),
         ("REMNDR", "getRemndrLttotPblancCmpet"), ("OPT", "getOPTLttotPblancCmpet"),
         ("PBLPVT", "getPblPvtRentLttotPblancCmpet")]
SCORE = "getAptLttotPblancScore"


def env():
    d = {}
    for line in io.open(ENV, encoding="utf-8-sig"):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1); d[k.strip()] = v.strip()
    return d


def pages(K, op):
    out, page = [], 1
    while True:
        u = B + op + "?serviceKey=" + K + "&" + urllib.parse.urlencode({"page": page, "perPage": 1000})
        for t in range(3):
            try:
                with urllib.request.urlopen(u, timeout=60) as r:
                    j = json.loads(r.read().decode("utf-8")); break
            except Exception as ex:
                if t == 2: raise RuntimeError(f"{op} page {page}: {str(ex)[:120]}")
                time.sleep(2 * (t + 1))
        tot = int(j.get("totalCount") or 0); d = j.get("data") or []
        out += d
        if len(out) >= tot or not d:
            if len(out) < tot: raise RuntimeError(f"{op}: {len(out)}/{tot} 만 받음")
            return out
        page += 1; time.sleep(0.15)


def 수(v):
    try: return int(str(v).replace(",", "").strip())
    except Exception: return None


def 률(v):
    s = str(v or "").strip()
    m = re.match(r"^\(\s*△\s*(\d+)\s*\)$", s)          # '(△30)' = 미달 30세대
    if m: return None, int(m.group(1))
    try: return float(s.replace(",", "")), None
    except Exception: return None, None


def 점(v):
    try: return float(str(v).strip())
    except Exception: return None                         # '-' = 없음


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--probe", action="store_true"); a = ap.parse_args()
    e = env(); key = e.get("DATA_GO_KR_KEY", "")
    if not key: sys.exit(".env 의 DATA_GO_KR_KEY 가 비어 있습니다")
    K = key if "%" in key else urllib.parse.quote(key)
    got = {k: pages(K, op) for k, op in CMPET}
    sc = pages(K, SCORE)
    for k, v in got.items(): print(f"{k}: {len(v):,}행", flush=True)
    print(f"가점: {len(sc):,}행", flush=True)
    if a.probe: return

    import pymssql
    conn = pymssql.connect(server=e.get("DB_HOST", "127.0.0.1"), port=int(e.get("DB_PORT", 11433)),
                           user=e.get("DB_USER", "sa"), password=e.get("DB_PASSWORD", ""),
                           database=e.get("DB_NAME", "Teomoony"), charset="UTF-8", autocommit=False)
    cur = conn.cursor()
    cur.execute("SELECT house_manage_no, pblanc_no FROM silver.applyhome_pblanc")
    우리 = {(str(r[0]), str(r[1])) for r in cur.fetchall()}
    n = 0
    for kind, rows in got.items():
        for x in rows:
            k = (str(x.get("HOUSE_MANAGE_NO")), str(x.get("PBLANC_NO")))
            if k not in 우리: continue
            ty = (x.get("HOUSE_TY") or "").strip() or "-"
            순위 = int(x.get("SUBSCRPT_RANK_CODE") or 0)
            if kind == "APT":      gk, gn = x.get("RESIDE_SECD"), x.get("RESIDE_SENM")
            elif kind == "URBTY":  gk, gn = x.get("RESIDNT_PRIOR_AT"), x.get("RESIDNT_PRIOR_SENM")
            elif kind == "PBLPVT": gk, gn = x.get("SPSPLY_KND_CODE"), x.get("SPSPLY_KND_NM")
            elif kind == "REMNDR": gk, gn = x.get("REMNDR_HSHLD_PBLANC_TYCD"), None
            else:                  gk, gn = None, None
            gk = str(gk or "-")
            r_, 미달 = 률(x.get("CMPET_RATE"))
            vals = (gn, kind, x.get("MODEL_NO"), 수(x.get("SUPLY_HSHLDCO")), 수(x.get("REQ_CNT")), x.get("CMPET_RATE"),
                    r_, 미달, json.dumps(x, ensure_ascii=False))
            pk = k + (ty, 순위, gk)
            cur.execute("""UPDATE silver.applyhome_cmpet SET 구분이름=%s, 공고종류=%s, model_no=%s, 공급=%s, 접수=%s, 경쟁률원문=%s,
                             경쟁률=%s, 미달=%s, raw_json=%s, loaded_at=SYSDATETIME()
                            WHERE house_manage_no=%s AND pblanc_no=%s AND 주택형=%s AND 순위=%s AND 구분키=%s""", vals + pk)
            if cur.rowcount == 0:
                cur.execute("""INSERT INTO silver.applyhome_cmpet (구분이름, 공고종류, model_no, 공급, 접수, 경쟁률원문, 경쟁률, 미달, raw_json,
                                 house_manage_no, pblanc_no, 주택형, 순위, 구분키) VALUES (""" + ",".join(["%s"] * 14) + ")", vals + pk)
            n += 1
    m = 0
    for x in sc:
        k = (str(x.get("HOUSE_MANAGE_NO")), str(x.get("PBLANC_NO")))
        if k not in 우리: continue
        ty = (x.get("HOUSE_TY") or "").strip() or "-"
        vals = (x.get("RESIDE_SENM"), x.get("MODEL_NO"), 점(x.get("LWET_SCORE")), 점(x.get("AVRG_SCORE")), 점(x.get("TOP_SCORE")),
                json.dumps(x, ensure_ascii=False))
        pk = k + (ty, str(x.get("RESIDE_SECD") or "-"))
        cur.execute("""UPDATE silver.applyhome_score SET 구분이름=%s, model_no=%s, 최저=%s, 평균=%s, 최고=%s, raw_json=%s, loaded_at=SYSDATETIME()
                        WHERE house_manage_no=%s AND pblanc_no=%s AND 주택형=%s AND 구분키=%s""", vals + pk)
        if cur.rowcount == 0:
            cur.execute("""INSERT INTO silver.applyhome_score (구분이름, model_no, 최저, 평균, 최고, raw_json, house_manage_no, pblanc_no, 주택형, 구분키)
                           VALUES (""" + ",".join(["%s"] * 10) + ")", vals + pk)
        m += 1
    conn.commit()
    cur.execute("SELECT COUNT(DISTINCT house_manage_no) FROM silver.applyhome_cmpet")
    print(f"넣음: 경쟁률 {n:,}행 · 가점 {m:,}행 · 경쟁률 있는 주택 {cur.fetchone()[0]:,} / 우리 공고 {len(우리):,}", flush=True)
    conn.close()


if __name__ == "__main__":
    main()
