# -*- coding: utf-8 -*-
"""load_applyhome - 청약홈 분양정보(한국부동산원) 공고 · 주택형 적재  2026-10-21

  py load_applyhome.py            # 서울 전체 + 경기 중 안양
  py load_applyhome.py --probe    # 받기만 하고 몇 건인지 말한다(DB 안 씀)

★ 출처: api.odcloud.kr/api/ApplyhomeInfoDetailSvc/v1
    getAPTLttotPblancDetail  공고(주소 · 공급세대 · 입주예정월 · 일정)
    getAPTLttotPblancMdl     주택형(전용 · 공급세대 · 분양최고금액)
  키 = .env DATA_GO_KR_KEY. 지역 거르기는 SUBSCRPT_AREA_CODE_NM(서울 · 경기) 다음 주소의 '안양시'.
★ 주소는 **문자열**이다. 조각(시군구 · 동 · 산 · 본번 · 부번)만 뽑고, 법정동 코드는 meta.lawd_code 에서 찾고,
  PNU 는 SQL 의 meta.fn_make_pnu 한 자리에서만 만든다(정책 1장). 못 풀면 NULL — 추측하지 않는다.
  '개포1동' 처럼 **행정동 이름**으로 쓴 주소는 숫자를 떼고(개포동) 법정동에서 다시 찾는다 — 근거 칸에 그렇게 적는다.
★ 단지 연결은 290 의 gold.usp_refresh_applyhome_link 가 한다(법정동 · 입주월 · 세대 · 500m). 끝에 부른다.
★ 같은 공고(관리번호+공고번호)가 다시 오면 고쳐 쓴다(정정 공고). 원문은 raw_json 에 그대로 남긴다.
"""
import argparse, io, json, os, re, sys, time
import urllib.parse, urllib.request
import pymssql

HERE = os.path.dirname(os.path.abspath(__file__))
ENV  = os.path.join(HERE, "..", ".env")
B    = "https://api.odcloud.kr/api/ApplyhomeInfoDetailSvc/v1/"

R = re.compile(r'(서울특별시|서울시|경기도)\s+(?:(안양시)\s*)?(?:(\S+구)\s+)?'
               r'(\S+?(?:동\d*가|\d*동|가))\s*(산)?\s*(\d+)(?:\s*-\s*(\d+))?')

# ★ 2026-10-21 밤: '못 품' 42건 대부분이 **도로명 주소**였다("노원로 495 (상계동 690)", "도봉로 232 (미아동)").
#   1) 괄호 안이나 뒤쪽에 '동 번지' 가 있으면 그걸 쓴다 — 근거 '괄호 안 지번'
#   2) 없으면 도로명·건물번호만 떼어 둔다 — SQL(gold.usp_applyhome_road_to_jibun, 296)이 대장 도로명과 대조해
#      **후보가 하나일 때만** 지번을 채운다. 여기서 추측하지 않는다.
SGG = re.compile(r'(서울특별시|서울시|경기도)\s+(?:(안양시)\s*)?(\S+구)')
PAREN = re.compile(r'(?:\(|,\s*\S+구\s+)\s*([가-힣0-9]+?(?:동\d*가|\d*동|가))\s+(산\s*)?(\d+)(?:-(\d+))?(?![\d.])')
ROAD = re.compile(r'(?:서울특별시|서울시|경기도)\s+(?:안양시\s*)?\S+구\s+([가-힣0-9.]+?(?:대로|로|길)(?:\s*\d+(?:번)?(?:가)?길)?)'
                  r'\s*(\d+)(?:-(\d+))?(?=$|[\s(,일번])')


def 조각(adr):
    """주소 문자열 → 조각. 돌려주는 것: dict(sgg, emd, san, bun, ji, 도로, 건물본번, 건물부번, 근거)"""
    a = re.sub(r'([가-힣]+로)\s+(\d+가)(?=\s)', r'\1\2', adr or '')      # '한강로 2가 210-1' → '한강로2가 210-1'
    d = dict(sgg=None, emd=None, san=None, bun=None, ji=None, 도로=None, 건물본번=None, 건물부번=None, 근거="못 품")
    m = R.search(a)
    if m:
        d.update(sgg=(m.group(2) or "") + (m.group(3) or ""), emd=m.group(4), san="1" if m.group(5) else "0",
                 bun=m.group(6), ji=m.group(7) or "0", 근거="법정동 그대로")
        return d
    g = SGG.search(a)
    if not g: return d
    d["sgg"] = (g.group(2) or "") + g.group(3)
    p = PAREN.search(a)
    if p:
        d.update(emd=p.group(1), san="1" if p.group(2) else "0", bun=p.group(3), ji=p.group(4) or "0", 근거="괄호 안 지번")
        return d
    r = ROAD.search(a)
    if r:
        d.update(도로=re.sub(r"\s+", "", r.group(1)), 건물본번=int(r.group(2)), 건물부번=int(r.group(3)) if r.group(3) else None,
                 근거="도로명만 — 대장 대조 대기")
    return d


def env():
    d = {}
    for line in io.open(ENV, encoding="utf-8-sig"):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1); d[k.strip()] = v.strip()
    return d


def pages(key, op, cond):
    out, page = [], 1
    while True:
        p = {"page": page, "perPage": 500, "serviceKey": key}; p.update(cond)
        url = B + op + "?" + urllib.parse.urlencode(p, safe="%")
        for a in range(3):
            try:
                with urllib.request.urlopen(url, timeout=60) as r:
                    j = json.loads(r.read().decode("utf-8")); break
            except Exception as e:
                if a == 2: raise RuntimeError(f"{op} {cond} page {page}: {e}")
                time.sleep(2 * (a + 1))
        d = j.get("data", []); out += d
        if len(out) >= int(j.get("matchCount") or 0) or not d:
            return out
        page += 1; time.sleep(0.3)


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--probe", action="store_true")
    # ★ 2026-10-29 사장님 "남은것도 너가해": 전국 — 지역 거르기 없이 받고 주소는 applyhome_addr(전국 · 마스터 이름 글자 그대로 · 하나일 때만)로 푼다
    ap.add_argument("--nation", action="store_true"); a = ap.parse_args()
    e = env(); key = e.get("DATA_GO_KR_KEY", "")
    if not key: sys.exit(".env 의 DATA_GO_KR_KEY 가 비어 있습니다")

    # ★ 2026-10-22 (299): APT 말고도 받는다 — 같은 서비스의 다른 목록. (종류, 공고 목록, 주택형 목록)
    KINDS = [("APT", "getAPTLttotPblancDetail", "getAPTLttotPblancMdl"),
             ("URBTY", "getUrbtyOfctlLttotPblancDetail", "getUrbtyOfctlLttotPblancMdl"),   # 오피스텔 · 도시형생활주택
             ("REMNDR", "getRemndrLttotPblancDetail", "getRemndrLttotPblancMdl"),          # 무순위 · 불법행위 재공급
             ("PBLPVT", "getPblPvtRentLttotPblancDetail", "getPblPvtRentLttotPblancMdl"),  # 공공지원민간임대
             ("OPT", "getOPTLttotPblancDetail", "getOPTLttotPblancMdl")]                   # 임의공급
    pbl, mdl = [], []
    for kind, op_d, op_m in KINDS:
        if a.nation:
            these = pages(key, op_d, {})
            for x in these: x["_kind"] = kind
            pbl += these; m0 = len(mdl)
            nos = {x["HOUSE_MANAGE_NO"] for x in these}
            for m in pages(key, op_m, {}):            # 주택형도 통째로(공고마다 부르면 수천 번)
                if m.get("HOUSE_MANAGE_NO") in nos: m["_kind"] = kind; mdl.append(m)
            print(f"{kind}: 공고 전국 {len(these)} · 주택형 {len(mdl) - m0}", flush=True)
            continue
        seoul = pages(key, op_d, {"cond[SUBSCRPT_AREA_CODE_NM::EQ]": "서울"})
        gg    = pages(key, op_d, {"cond[SUBSCRPT_AREA_CODE_NM::EQ]": "경기"})
        these = seoul + [x for x in gg if "안양시" in (x.get("HSSPLY_ADRES") or "")]
        for x in these: x["_kind"] = kind
        pbl += these
        m0 = len(mdl)
        for no in sorted({x["HOUSE_MANAGE_NO"] for x in these}):
            for m in pages(key, op_m, {"cond[HOUSE_MANAGE_NO::EQ]": no}):
                m["_kind"] = kind; mdl.append(m)
        print(f"{kind}: 공고 서울 {len(seoul)} · 경기 {len(gg)} 중 안양 {len(these) - len(seoul)} → {len(these)} · 주택형 {len(mdl) - m0}", flush=True)
    print(f"공고 {len(pbl)} · 주택형 {len(mdl)}행", flush=True)
    if a.probe: return

    conn = pymssql.connect(server=e.get("DB_HOST", "127.0.0.1"), port=int(e.get("DB_PORT", 11433)),
                           user=e.get("DB_USER", "sa"), password=e.get("DB_PASSWORD", ""),
                           database=e.get("DB_NAME", "Teomoony"), charset="UTF-8", autocommit=False)
    cur = conn.cursor()
    cur.execute("""SELECT lawd_cd, REPLACE(sgg_nm, ' ', ''), emd_nm FROM meta.lawd_code
                    WHERE ri_nm IS NULL AND emd_nm IS NOT NULL AND is_abolished = 0
                      AND (LEFT(lawd_cd, 2) = '11' OR LEFT(lawd_cd, 5) IN ('41171', '41173'))""")
    by = {}; anyang = {}
    for cd, sgg, emd in cur.fetchall():
        by[(sgg, emd)] = cd
        if cd.startswith(("41171", "41173")): anyang.setdefault(emd, []).append(cd)

    if a.nation:
        from applyhome_addr import 사전, 조각 as 조각전국
        cur.execute("IF COL_LENGTH('silver.applyhome_pblanc', '주소_sgg_cd') IS NULL ALTER TABLE silver.applyhome_pblanc ADD 주소_sgg_cd CHAR(5) NULL"); conn.commit()
        cur.execute("SELECT lawd_cd, sido_nm, sgg_nm, emd_nm, ri_nm, is_abolished FROM meta.lawd_code"); 전국사전 = 사전(cur.fetchall())
    def 풀기(adr):
        if a.nation:
            d = 조각전국(adr, 전국사전); return d, d["cd"]
        d = 조각(adr)
        if not d["emd"]: return d, None
        sgg, emd = d["sgg"], d["emd"]
        def 찾기(e2):
            if "안양시" not in sgg: return by.get((sgg, e2))
            if sgg != "안양시": return by.get((sgg, e2))
            c = anyang.get(e2, []); return c[0] if len(c) == 1 else None   # 안양시 + 구 없음 → 두 구 중 하나뿐이면
        cd = 찾기(emd)
        if not cd and re.search(r"\d+동$", emd):
            cd = 찾기(re.sub(r"\d+동$", "동", emd))
            if cd: d["근거"] += " · 행정동 이름에서 숫자 뗌"
        if not cd: d["근거"] += " · 법정동 못 찾음"
        return d, cd

    n = 0; 못 = 0
    for x in pbl:
        d, cd = 풀기(x.get("HSSPLY_ADRES"))
        if not cd: 못 += 1
        첫 = lambda *ks: next((x.get(k) for k in ks if x.get(k)), None)   # 종류마다 칸 이름이 조금씩 다르다
        vals = (x.get("HOUSE_NM"), x.get("HSSPLY_ADRES"), d["sgg"], d["emd"], d["san"], d["bun"], d["ji"], d["근거"], cd,
                d["도로"], d["건물본번"], d["건물부번"],
                x.get("HOUSE_SECD_NM"), 첫("HOUSE_DTL_SECD_NM", "HOUSE_DETAIL_SECD_NM"), x.get("RENT_SECD_NM"),
                int(x.get("TOT_SUPLY_HSHLDCO") or 0) or None, x.get("RCRIT_PBLANC_DE"),
                첫("RCEPT_BGNDE", "SUBSCRPT_RCEPT_BGNDE", "SPSPLY_RCEPT_BGNDE", "GNRL_RCEPT_BGNDE"),
                첫("RCEPT_ENDDE", "SUBSCRPT_RCEPT_ENDDE", "GNRL_RCEPT_ENDDE", "SPSPLY_RCEPT_ENDDE"),
                x.get("PRZWNER_PRESNATN_DE"), (x.get("MVN_PREARNGE_YM") or None),
                x.get("BSNS_MBY_NM"), x.get("CNSTRCT_ENTRPS_NM"), x.get("PBLANC_URL"), x.get("SUBSCRPT_AREA_CODE_NM"),
                json.dumps(x, ensure_ascii=False), x["_kind"])
        k = (str(x["HOUSE_MANAGE_NO"]), str(x["PBLANC_NO"]))
        cur.execute("""UPDATE silver.applyhome_pblanc SET house_nm=%s, hssply_adres=%s, 주소_시군구=%s, 주소_동=%s, 주소_산=%s,
                         주소_본번=%s, 주소_부번=%s, 주소근거=%s, lawd_cd=%s, 주소_도로=%s, 주소_건물본번=%s, 주소_건물부번=%s, house_secd_nm=%s, house_dtl_secd_nm=%s, rent_secd_nm=%s,
                         tot_suply=%s, rcrit_pblanc_de=%s, rcept_bgnde=%s, rcept_endde=%s, przwner_de=%s, mvn_prearnge_ym=%s,
                         bsns_mby_nm=%s, cnstrct_entrps_nm=%s, pblanc_url=%s, subscrpt_area_nm=%s, raw_json=%s, 공고종류=%s, loaded_at=SYSDATETIME()
                        WHERE house_manage_no=%s AND pblanc_no=%s""", vals + k)
        if cur.rowcount == 0:
            cur.execute("""INSERT INTO silver.applyhome_pblanc (house_nm, hssply_adres, 주소_시군구, 주소_동, 주소_산, 주소_본번, 주소_부번,
                             주소근거, lawd_cd, 주소_도로, 주소_건물본번, 주소_건물부번, house_secd_nm, house_dtl_secd_nm, rent_secd_nm, tot_suply, rcrit_pblanc_de, rcept_bgnde,
                             rcept_endde, przwner_de, mvn_prearnge_ym, bsns_mby_nm, cnstrct_entrps_nm, pblanc_url, subscrpt_area_nm,
                             raw_json, 공고종류, house_manage_no, pblanc_no)
                           VALUES (""" + ",".join(["%s"] * 29) + ")", vals + k)
        if a.nation:
            cur.execute("UPDATE silver.applyhome_pblanc SET 주소_sgg_cd = %s WHERE house_manage_no = %s AND pblanc_no = %s", (d.get("sgg_cd"),) + k)
        n += 1
    for x in mdl:
        ty = x.get("HOUSE_TY") or x.get("TP") or ""
        m2 = re.match(r"\s*0*(\d+(?:\.\d+)?)", x.get("HOUSE_TY") or ""); 전용 = float(m2.group(1)) if m2 else None
        if x.get("EXCLUSE_AR"):          # 오피스텔·임대는 전용면적이 따로 온다
            try: 전용 = float(str(x["EXCLUSE_AR"]).replace(",", ""))
            except Exception: pass
        def i(v):
            try: return int(str(v).replace(",", ""))
            except Exception: return None
        def f(v):
            try: return float(str(v).replace(",", ""))
            except Exception: return None
        # ★ 분양가: APT·무순위·임의공급 = LTTOT_TOP_AMOUNT(최고) · 오피스텔/도시형 = SUPLY_AMOUNT · 공공지원민간임대는 **분양가가 아니라** 넣지 않는다
        금액 = None if x["_kind"] == "PBLPVT" else (i(x.get("LTTOT_TOP_AMOUNT")) if x.get("LTTOT_TOP_AMOUNT") else i(x.get("SUPLY_AMOUNT")))
        vals = (ty, 전용, f(x.get("SUPLY_AR")), i(x.get("SUPLY_HSHLDCO")), i(x.get("SPSPLY_HSHLDCO")),
                금액, json.dumps(x, ensure_ascii=False))
        k = (str(x["HOUSE_MANAGE_NO"]), str(x["PBLANC_NO"]), str(x["MODEL_NO"]))
        cur.execute("""UPDATE silver.applyhome_mdl SET house_ty=%s, 전용m2=%s, suply_ar=%s, suply_hshldco=%s, spsply_hshldco=%s,
                         top_amount_man=%s, raw_json=%s, loaded_at=SYSDATETIME()
                        WHERE house_manage_no=%s AND pblanc_no=%s AND model_no=%s""", vals + k)
        if cur.rowcount == 0:
            cur.execute("""INSERT INTO silver.applyhome_mdl (house_ty, 전용m2, suply_ar, suply_hshldco, spsply_hshldco, top_amount_man,
                             raw_json, house_manage_no, pblanc_no, model_no) VALUES (""" + ",".join(["%s"] * 10) + ")", vals + k)
    conn.commit()
    print(f"넣음: 공고 {n} (법정동 못 찾음 {못}) · 주택형 {len(mdl)}", flush=True)
    # (296 도로명 → 지번은 usp_refresh_applyhome_link 안에서 부른다 — 전국은 주소_sgg_cd 로)
    cur.execute("EXEC gold.usp_refresh_applyhome_link")
    r = cur.fetchone(); conn.commit()
    if r: print(f"연결: 공고 {r[0]} · 법정동 {r[1]} · 필지 {r[2]} · 이음 {r[3]} (단지에 {r[4]} · 대장 없는 신축에 {r[5]})")
    conn.close()


if __name__ == "__main__":
    main()
