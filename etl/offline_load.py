#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
offline_load - 저장된 raw XML 을 읽어 silver 에 적재 (검증용)

실제 적재기(teomoony_ingest.py)와 같은 매핑/SCD2 로직을 쓰되,
API 호출 대신 파일을 읽는다. 클라우드 컨테이너에서 실데이터 검증용.
"""
import glob, hashlib, io, os, sys
import xml.etree.ElementTree as ET
import pymssql

# 비밀번호를 소스에 박지 않는다. .env 의 DB_PASSWORD 를 읽고, 없으면 환경변수.
# (2026-10-16: 여기 평문으로 들어 있던 것을 걷어냈다. 다른 적재기들은 .env 를 쓴다)

HUB_BLD = {"silver.bld_basis_outline", "silver.bld_title", "silver.bld_recap_title", "silver.bld_atch_jibun", "silver.bld_expos",
           "silver.bld_jijigu", "silver.bld_flr_outline", "silver.bld_expos_pubuse_area", "silver.bld_hsprc"}
def hub_guard(t):
    """2026-10-25 대장 9종은 허브 파일에서 만든 표(hub_swap.py)로 바꿔 끼웠다 — API 로 받은 줄을 거기 섞지 않는다."""
    import os
    if t in HUB_BLD and os.environ.get("ALLOW_API_BLD") != "1":
        raise SystemExit(f"{t} 는 허브 대장 표입니다 — API 대장 적재는 멈췄습니다(hub_swap.py). 꼭 필요하면 ALLOW_API_BLD=1")

def _env(path=os.path.join(os.path.dirname(__file__), "..", ".env")):
    d = {}
    if os.path.exists(path):
        for ln in io.open(path, encoding="utf-8"):
            ln = ln.strip()
            if ln and not ln.startswith("#") and "=" in ln:
                k, v = ln.split("=", 1)
                d[k.strip()] = v.strip().strip('"').strip("'")
    return d

_E = _env()
DB = dict(server=_E.get("DB_HOST", "127.0.0.1"), port=int(_E.get("DB_PORT", 11433)),
          user=_E.get("DB_USER", "sa"),
          password=_E.get("DB_PASSWORD") or os.environ.get("SA_PW", ""),
          database=_E.get("DB_NAME", "Teomoony"), charset="UTF-8")
if not DB["password"]:
    sys.exit(".env 의 DB_PASSWORD 가 없습니다 (또는 환경변수 SA_PW).")
RAW = "/mnt/user-data/uploads/Teomoony/etl/raw"

NUM = ("_area","_cnt","_rat","_no","heit","_bun","_utcnt","_cert","_epi","_ar","_pclnd")
FLOAT_COLS = ("_area","_rat","_ar","_pclnd","heit","_cert","_epi")

OPS = {
 "getBrBasisOulnInfo": dict(
   target="silver.bld_basis_outline", keys=["mgm_bldrgst_pk"],
   pnu_from=("sigungu_cd","bjdong_cd","plat_gb_cd","bun","ji"), pnu_col="pnu",
   map={"mgmBldrgstPk":"mgm_bldrgst_pk","mgmUpBldrgstPk":"mgm_up_bldrgst_pk",
        "bldgId":"bldg_id","regstrGbCd":"regstr_gb_cd","regstrGbCdNm":"regstr_gb_nm",
        "regstrKindCd":"regstr_kind_cd","regstrKindCdNm":"regstr_kind_nm",
        "sigunguCd":"sigungu_cd","bjdongCd":"bjdong_cd","platGbCd":"plat_gb_cd",
        "bun":"bun","ji":"ji","platPlc":"plat_plc","bylotCnt":"bylot_cnt",
        "splotNm":"splot_nm","block":"block","lot":"lot",
        "naRoadCd":"na_road_cd","naBjdongCd":"na_bjdong_cd","naUgrndCd":"na_ugrnd_cd",
        "naMainBun":"na_main_bun","naSubBun":"na_sub_bun","newPlatPlc":"new_plat_plc",
        "bldNm":"bld_nm","jiyukCd":"jiyuk_cd","jiyukCdNm":"jiyuk_nm",
        "jiguCd":"jigu_cd","jiguCdNm":"jigu_nm","guyukCd":"guyuk_cd","guyukCdNm":"guyuk_nm",
        "crtnDay":"crtn_day"}),

 "getBrTitleInfo": dict(
   target="silver.bld_title", keys=["mgm_bldrgst_pk"],
   pnu_from=("sigungu_cd","bjdong_cd","plat_gb_cd","bun","ji"), pnu_col="pnu",
   map={"mgmBldrgstPk":"mgm_bldrgst_pk",
        "regstrGbCd":"regstr_gb_cd","regstrGbCdNm":"regstr_gb_nm",
        "regstrKindCd":"regstr_kind_cd","regstrKindCdNm":"regstr_kind_nm",
        "sigunguCd":"sigungu_cd","bjdongCd":"bjdong_cd","platGbCd":"plat_gb_cd",
        "bun":"bun","ji":"ji","platPlc":"plat_plc","bylotCnt":"bylot_cnt",
        "naRoadCd":"na_road_cd","naBjdongCd":"na_bjdong_cd","naUgrndCd":"na_ugrnd_cd",
        "naMainBun":"na_main_bun","naSubBun":"na_sub_bun","newPlatPlc":"new_plat_plc",
        "bldNm":"bld_nm","dongNm":"dong_nm","splotNm":"splot_nm","block":"block","lot":"lot",
        "mainAtchGbCd":"main_atch_gb_cd","mainAtchGbCdNm":"main_atch_gb_nm",
        "platArea":"plat_area","archArea":"arch_area","bcRat":"bc_rat","totArea":"tot_area",
        "vlRatEstmTotArea":"vl_rat_estm_tot_area","vlRat":"vl_rat",
        "totDongTotArea":"tot_dong_tot_area",
        "strctCd":"strct_cd","strctCdNm":"strct_nm","etcStrct":"etc_strct",
        "mainPurpsCd":"main_purps_cd","mainPurpsCdNm":"main_purps_nm","etcPurps":"etc_purps",
        "roofCd":"roof_cd","roofCdNm":"roof_nm","etcRoof":"etc_roof",
        "hhldCnt":"hhld_cnt","fmlyCnt":"fmly_cnt","hoCnt":"ho_cnt","heit":"heit",
        "grndFlrCnt":"grnd_flr_cnt","ugrndFlrCnt":"ugrnd_flr_cnt",
        "rideUseElvtCnt":"ride_use_elvt_cnt","emgenUseElvtCnt":"emgen_use_elvt_cnt",
        "atchBldCnt":"atch_bld_cnt","atchBldArea":"atch_bld_area",
        "indrMechUtcnt":"indr_mech_utcnt","indrMechArea":"indr_mech_area",
        "oudrMechUtcnt":"oudr_mech_utcnt","oudrMechArea":"oudr_mech_area",
        "indrAutoUtcnt":"indr_auto_utcnt","indrAutoArea":"indr_auto_area",
        "oudrAutoUtcnt":"oudr_auto_utcnt","oudrAutoArea":"oudr_auto_area",
        "pmsDay":"pms_day","stcnsDay":"stcns_day","useAprDay":"use_apr_day",
        "pmsnoYear":"pmsno_year","pmsnoKikCd":"pmsno_kik_cd","pmsnoKikCdNm":"pmsno_kik_nm",
        "pmsnoGbCd":"pmsno_gb_cd","pmsnoGbCdNm":"pmsno_gb_nm",
        "engrGrade":"engr_grade","engrRat":"engr_rat","engrEpi":"engr_epi",
        "gnBldGrade":"gn_bld_grade","gnBldCert":"gn_bld_cert",
        "itgBldGrade":"itg_bld_grade","itgBldCert":"itg_bld_cert",
        "rserthqkDsgnApplyYn":"rserthqk_dsgn_apply_yn","rserthqkAblty":"rserthqk_ablty",
        "crtnDay":"crtn_day"}),

 "getBrRecapTitleInfo": dict(
   target="silver.bld_recap_title", keys=["mgm_bldrgst_pk"],
   pnu_from=("sigungu_cd","bjdong_cd","plat_gb_cd","bun","ji"), pnu_col="pnu",
   map={"mgmBldrgstPk":"mgm_bldrgst_pk","sigunguCd":"sigungu_cd","bjdongCd":"bjdong_cd",
        "platGbCd":"plat_gb_cd","bun":"bun","ji":"ji","platPlc":"plat_plc",
        "newPlatPlc":"new_plat_plc","bldNm":"bld_nm",
        "regstrGbCd":"regstr_gb_cd","regstrGbCdNm":"regstr_gb_nm",
        "regstrKindCd":"regstr_kind_cd","regstrKindCdNm":"regstr_kind_nm",
        "newOldRegstrGbCd":"new_old_regstr_gb_cd","newOldRegstrGbCdNm":"new_old_regstr_gb_nm",
        "naRoadCd":"na_road_cd","naBjdongCd":"na_bjdong_cd","naUgrndCd":"na_ugrnd_cd",
        "naMainBun":"na_main_bun","naSubBun":"na_sub_bun",
        "splotNm":"splot_nm","block":"block","lot":"lot","bylotCnt":"bylot_cnt",
        "platArea":"plat_area","archArea":"arch_area","bcRat":"bc_rat","totArea":"tot_area",
        "vlRat":"vl_rat","vlRatEstmTotArea":"vl_rat_estm_tot_area",
        "mainPurpsCd":"main_purps_cd","mainPurpsCdNm":"main_purps_nm","etcPurps":"etc_purps",
        "mainBldCnt":"main_bld_cnt","atchBldCnt":"atch_bld_cnt","atchBldArea":"atch_bld_area",
        "hhldCnt":"hhld_cnt","fmlyCnt":"fmly_cnt","hoCnt":"ho_cnt","totPkngCnt":"tot_pkng_cnt",
        "indrMechUtcnt":"indr_mech_utcnt","indrMechArea":"indr_mech_area",
        "oudrMechUtcnt":"oudr_mech_utcnt","oudrMechArea":"oudr_mech_area",
        "indrAutoUtcnt":"indr_auto_utcnt","indrAutoArea":"indr_auto_area",
        "oudrAutoUtcnt":"oudr_auto_utcnt","oudrAutoArea":"oudr_auto_area",
        "engrGrade":"engr_grade","engrRat":"engr_rat","engrEpi":"engr_epi",
        "gnBldGrade":"gn_bld_grade","gnBldCert":"gn_bld_cert",
        "itgBldGrade":"itg_bld_grade","itgBldCert":"itg_bld_cert",
        "pmsnoYear":"pmsno_year","pmsnoKikCd":"pmsno_kik_cd","pmsnoKikCdNm":"pmsno_kik_nm",
        "pmsnoGbCd":"pmsno_gb_cd","pmsnoGbCdNm":"pmsno_gb_nm",
        "useAprDay":"use_apr_day","pmsDay":"pms_day","stcnsDay":"stcns_day",
        "crtnDay":"crtn_day"}),

 "getBrAtchJibunInfo": dict(
   target="silver.bld_atch_jibun", keys=["mgm_bldrgst_pk","atch_pnu"],
   pnu_from=("atch_sigungu_cd","atch_bjdong_cd","atch_plat_gb_cd","atch_bun","atch_ji"),
   pnu_col="atch_pnu",
   map={"mgmBldrgstPk":"mgm_bldrgst_pk","platPlc":"plat_plc",
        "atchSigunguCd":"atch_sigungu_cd","atchBjdongCd":"atch_bjdong_cd",
        "atchPlatGbCd":"atch_plat_gb_cd","atchBun":"atch_bun","atchJi":"atch_ji",
        "atchRegstrGbCd":"atch_gb_cd","crtnDay":"crtn_day"}),
}


def to_native(col, v):
    if v is None: return None
    s = str(v).strip()
    if s == "": return None
    if any(h in col for h in NUM):
        try:
            f = float(s)
        except ValueError:
            return None
        return f if any(h in col for h in FLOAT_COLS) else int(f)
    return s


def rowhash(m, cols):
    h = hashlib.sha256()
    for c in cols:
        h.update(str(m.get(c, "")).encode()); h.update(b"\x1f")
    return h.digest()


def load(op, spec, cur):
    files = sorted(glob.glob(os.path.join(RAW, f"{op}_p*.xml")))
    rows = []
    unmapped = set()
    for fp in files:
        for item in ET.parse(fp).getroot().iter("item"):
            d = {c.tag: ((c.text or "").strip() or None) for c in item}
            unmapped |= (set(d) - set(spec["map"]) - {"rnum"})
            rows.append(d)

    cols = list(dict.fromkeys(spec["map"].values()))
    if spec["pnu_col"] and spec["pnu_col"] not in cols:
        cols.append(spec["pnu_col"])

    n = 0
    for raw in rows:
        m = {dst: to_native(dst, raw.get(src)) for src, dst in spec["map"].items()}
        if spec["pnu_col"]:
            cur.execute("SELECT meta.fn_make_pnu(%s,%s,%s,%s,%s)",
                        tuple(None if m.get(c) is None else str(m.get(c))
                              for c in spec["pnu_from"]))
            m[spec["pnu_col"]] = cur.fetchone()[0]

        keys = spec["keys"]
        hub_guard(spec["target"])
        if any(m.get(k) in (None, "") for k in keys):
            continue
        rh = rowhash(m, cols)
        where = " AND ".join(f"{k} = %s" for k in keys)
        kv = tuple(m[k] for k in keys)

        cur.execute(f"UPDATE {spec['target']} SET is_current=0, valid_to=SYSDATETIME() "
                    f"WHERE is_current=1 AND {where} AND row_hash <> %s", kv + (rh,))
        cur.execute(
            f"IF NOT EXISTS (SELECT 1 FROM {spec['target']} WHERE is_current=1 AND {where}) "
            f"INSERT INTO {spec['target']} ({', '.join(cols)}, row_hash) "
            f"VALUES ({', '.join(['%s']*len(cols))}, %s)",
            kv + tuple(m.get(c) for c in cols) + (rh,))
        n += 1
    return n, len(rows), sorted(unmapped)


def main():
    conn = pymssql.connect(**DB, autocommit=False)
    cur = conn.cursor()
    print("기존 데이터 정리 (합성 샘플 포함)")
    for t in ("gold.complex_pnu","gold.complex_bld","gold.complex_identity","gold.complex",
              "silver.bld_atch_jibun","silver.bld_recap_title","silver.bld_title",
              "silver.bld_basis_outline","silver.land_char","silver.road_addr"):
        cur.execute(f"DELETE FROM {t}")
    cur.execute("DBCC CHECKIDENT('gold.complex', RESEED, 1) WITH NO_INFOMSGS  -- 빈 테이블이면 다음 행이 이 값을 그대로 쓴다 (0 을 주면 0 부터 시작)")
    conn.commit()

    for op, spec in OPS.items():
        n, total, unmapped = load(op, spec, cur)
        conn.commit()
        print(f"  {op:26s} {n:5d}/{total} 적재"
              + (f"   [미매핑: {', '.join(unmapped)}]" if unmapped else ""))

    print("\n단지 구성 실행")
    cur.execute("EXEC gold.usp_build_complexes @sigungu_cd='11110', @bjdong_cd='10100'")
    conn.commit()
    conn.close()
    print("완료")


if __name__ == "__main__":
    main()
