# -*- coding: utf-8 -*-
"""hub_views - 허브 대장 표(hub.t03xx · hub.l0306 · hub.l0308) 위에 **우리 대장 표(silver.bld_*)와 같은 모양의 뷰**를 만든다 (2026-10-25 사장님
  "파일로 이미 받았으니 load data 로 올린 다음 그 테이블을 쓰면 되는 거 아냐?" — 복사하지 않고 그대로 쓴다)
  py hub_views.py > ..\\deploy\\sql\\353_hub_views.sql      (먼저 schema hubv 에 만들어 서울로 대조 → 맞으면 silver 이름으로 바꿔 끼운다)

  ★ 값 바꾸기는 API 적재(teomoony_ingest.to_native)와 같게: 앞뒤 빈칸 자름 · 빈 글자 = NULL · 정수는 int(float(글자)) · 소수는 그 칸의 decimal.
  ★ PNU = meta.fn_make_pnu 와 같은 식(인라인 — 스칼라 함수는 줄마다 불려 느리다).
  ★ 지금 줄 = hub 의 마지막월 IS NULL(가장 최근 달에도 있는 줄). valid_from = 처음월 1일 · valid_to = 9999-12-31 · is_current = 1.
  ★ 층별개요 · 전유공용면적은 API 적재처럼 같은 자연키 줄을 합친다(면적 SUM · seg_cnt = 줄 수). 나머지 칸은 MIN(API 는 '처음 온 줄' — 어차피 정해진 순서가 아니다).
  ★ 관리 PK 는 허브 그대로(NVARCHAR) — CAST 하면 색인을 못 탄다(비교하는 쪽 VARCHAR 가 NVARCHAR 로 올라가며 seek 된다).
"""
import json, os, re
HERE = os.path.dirname(os.path.abspath(__file__))

def T(c): return f"NULLIF(LTRIM(RTRIM([{c}])), N'')"
def V(c, n): return f"CAST({T(c)} AS VARCHAR({n}))"
def NV(c, n): return f"CAST({T(c)} AS NVARCHAR({n}))"
def C(c, n): return f"CAST({T(c)} AS CHAR({n}))"
def I(c): return f"TRY_CONVERT(INT, TRY_CONVERT(DECIMAL(38, 9), {T(c)}))"
def D(c, p, s): return f"TRY_CONVERT(DECIMAL({p}, {s}), TRY_CONVERT(FLOAT, {T(c)}))"
def PNU(sg, bj, gb, b, j):
    sg_, bj_, b_, j_ = T(sg), T(bj), T(b), T(j)
    return (f"CASE WHEN LEN({sg_}) = 5 AND LEN({bj_}) = 5 AND ({b_} IS NULL OR TRY_CAST({b_} AS INT) IS NOT NULL) AND ({j_} IS NULL OR TRY_CAST({j_} AS INT) IS NOT NULL) "
            f"THEN CAST({sg_} + {bj_} + CASE LTRIM(RTRIM(ISNULL([{gb}], N'0'))) WHEN N'1' THEN N'2' ELSE N'1' END "
            f"+ RIGHT(N'0000' + CAST(ISNULL(TRY_CAST({b_} AS INT), 0) AS NVARCHAR(10)), 4) + RIGHT(N'0000' + CAST(ISNULL(TRY_CAST({j_} AS INT), 0) AS NVARCHAR(10)), 4) AS CHAR(19)) END")

PK = "[관리_건축물대장_PK]"
지번 = [("sigungu_cd", C("시군구_코드", 5)), ("bjdong_cd", C("법정동_코드", 5)), ("plat_gb_cd", V("대지_구분_코드", 1)),
        ("bun", V("번", 10)), ("ji", V("지", 10)), ("pnu", PNU("시군구_코드", "법정동_코드", "대지_구분_코드", "번", "지")),
        ("plat_plc", NV("대지_위치", 300))]
도로 = [("na_road_cd", C("새주소_도로_코드", 12)), ("na_bjdong_cd", C("새주소_법정동_코드", 5)), ("na_ugrnd_cd", V("새주소_지상지하_코드", 1)),
        ("na_main_bun", I("새주소_본_번")), ("na_sub_bun", I("새주소_부_번")), ("new_plat_plc", NV("도로명_대지_위치", 300))]
대장 = [("regstr_gb_cd", V("대장_구분_코드", 2)), ("regstr_gb_nm", NV("대장_구분_코드_명", 40)),
        ("regstr_kind_cd", V("대장_종류_코드", 2)), ("regstr_kind_nm", NV("대장_종류_코드_명", 40))]
특수 = [("splot_nm", NV("특수지_명", 100)), ("block", NV("블록", 40)), ("lot", NV("로트", 40))]
면적들 = lambda: [("plat_area", D("대지_면적", 19, 5)), ("arch_area", D("건축_면적", 19, 5)), ("bc_rat", D("건폐_율", 14, 5)), ("tot_area", D("연면적", 19, 5)),
                  ("vl_rat_estm_tot_area", D("용적_률_산정_연면적", 19, 5)), ("vl_rat", D("용적_률", 14, 5))]
주차 = [("indr_mech_utcnt", I("옥내_기계식_대수")), ("indr_mech_area", D("옥내_기계식_면적", 19, 5)), ("oudr_mech_utcnt", I("옥외_기계식_대수")),
        ("oudr_mech_area", D("옥외_기계식_면적", 19, 5)), ("indr_auto_utcnt", I("옥내_자주식_대수")), ("indr_auto_area", D("옥내_자주식_면적", 19, 5)),
        ("oudr_auto_utcnt", I("옥외_자주식_대수")), ("oudr_auto_area", D("옥외_자주식_면적", 19, 5))]
허가 = [("pms_day", C("허가_일", 8)), ("stcns_day", C("착공_일", 8)), ("use_apr_day", C("사용승인_일", 8)), ("pmsno_year", C("허가번호_년", 4)),
        ("pmsno_kik_cd", V("허가번호_기관_코드", 20)), ("pmsno_kik_nm", NV("허가번호_기관_코드_명", 80)), ("pmsno_gb_cd", V("허가번호_구분_코드", 10)),
        ("pmsno_gb_nm", NV("허가번호_구분_코드_명", 80))]
에너지 = [("engr_grade", NV("에너지효율_등급", 40)), ("engr_rat", D("에너지절감_율", 13, 3)), ("engr_epi", D("에너지_EPI점수", 13, 3)),
          ("gn_bld_grade", NV("친환경_건축물_등급", 40)), ("gn_bld_cert", D("친환경_건축물_인증점수", 13, 3)),
          ("itg_bld_grade", NV("지능형_건축물_등급", 40)), ("itg_bld_cert", D("지능형_건축물_인증점수", 13, 3))]
용도 = [("main_purps_cd", V("주_용도_코드", 10)), ("main_purps_nm", NV("주_용도_코드_명", 100)), ("etc_purps", NV("기타_용도", 400))]
구조 = [("strct_cd", V("구조_코드", 10)), ("strct_nm", NV("구조_코드_명", 100)), ("etc_strct", NV("기타_구조", 200))]
끝 = [("crtn_day", C("생성_일자", 8))]
SCD = lambda sk: [(sk, "[행_sk]"), ("row_hash", "[행해시]"), ("src_run_id", "CAST(NULL AS BIGINT)"),
                  ("valid_from", "CAST(CAST([처음월] + '01' AS DATE) AS DATETIME2(0))"), ("valid_to", "CAST('9999-12-31' AS DATETIME2(0))"), ("is_current", "CAST(1 AS BIT)")]

VIEWS = {
 "bld_basis_outline": ("hub.t0301", SCD("basis_sk") + [("mgm_bldrgst_pk", PK), ("mgm_up_bldrgst_pk", V("관리_상위_건축물대장_PK", 50)),
     ("root_bldrgst_pk", f"CASE WHEN {T('관리_상위_건축물대장_PK')} IS NULL OR {T('관리_상위_건축물대장_PK')} = N'0' THEN {PK} ELSE {T('관리_상위_건축물대장_PK')} END"),
     ("bldg_id", "CAST(NULL AS VARCHAR(30))")] + 대장 + 지번 + [("bylot_cnt", I("외필지_수"))] + 특수 + 도로 + [("bld_nm", NV("건물_명", 200)),
     ("jiyuk_cd", V("지역_코드", 20)), ("jiyuk_nm", NV("지역_코드_명", 100)), ("jigu_cd", V("지구_코드", 20)), ("jigu_nm", NV("지구_코드_명", 100)),
     ("guyuk_cd", V("구역_코드", 20)), ("guyuk_nm", NV("구역_코드_명", 100))] + 끝),
 "bld_recap_title": ("hub.t0302", SCD("recap_sk") + [("mgm_bldrgst_pk", PK)] + 대장 + [("new_old_regstr_gb_cd", V("신_구_대장_구분_코드", 2)),
     ("new_old_regstr_gb_nm", NV("신_구_대장_구분_코드_명", 40))] + 지번 + [("bylot_cnt", I("외필지_수"))] + 특수 + 도로 + [("bld_nm", NV("건물_명", 200))]
     + 면적들() + 용도 + [("hhld_cnt", I("세대_수")), ("fmly_cnt", I("가구_수")), ("main_bld_cnt", I("주_건축물_수")), ("atch_bld_cnt", I("부속_건축물_수")),
     ("atch_bld_area", D("부속_건축물_면적", 19, 5)), ("tot_pkng_cnt", I("총_주차_수"))] + 주차 + 허가 + [("ho_cnt", I("호_수"))] + 에너지 + 끝),
 "bld_title": ("hub.t0303", SCD("bld_title_sk") + [("mgm_bldrgst_pk", PK)] + 대장 + 지번 + [("bylot_cnt", I("외필지_수"))] + 도로
     + [("bld_nm", NV("건물_명", 200)), ("dong_nm", NV("동_명", 100))] + 특수 + 면적들() + [("tot_dong_tot_area", D("총_동_연면적", 19, 5))] + 구조 + 용도
     + [("roof_cd", V("지붕_코드", 10)), ("roof_nm", NV("지붕_코드_명", 100)), ("etc_roof", NV("기타_지붕", 200)),
        ("hhld_cnt", I("세대_수")), ("fmly_cnt", I("가구_수")), ("ho_cnt", I("호_수")), ("heit", D("높이", 13, 3)),
        ("grnd_flr_cnt", I("지상_층_수")), ("ugrnd_flr_cnt", I("지하_층_수")), ("ride_use_elvt_cnt", I("승용_승강기_수")), ("emgen_use_elvt_cnt", I("비상용_승강기_수")),
        ("atch_bld_cnt", I("부속_건축물_수")), ("atch_bld_area", D("부속_건축물_면적", 19, 5))] + 주차 + 허가 + 에너지
     + [("main_atch_gb_cd", V("주_부속_구분_코드", 2)), ("main_atch_gb_nm", NV("주_부속_구분_코드_명", 40)),
        ("rserthqk_dsgn_apply_yn", V("내진_설계_적용_여부", 10)), ("rserthqk_ablty", NV("내진_능력", 100))] + 끝),
 "bld_atch_jibun": ("hub.t0305", SCD("atch_sk") + [("mgm_bldrgst_pk", PK), ("atch_sigungu_cd", C("부속_시군구_코드", 5)), ("atch_bjdong_cd", C("부속_법정동_코드", 5)),
     ("atch_plat_gb_cd", V("부속_대지_구분_코드", 1)), ("atch_bun", V("부속_번", 10)), ("atch_ji", V("부속_지", 10)),
     ("atch_pnu", PNU("부속_시군구_코드", "부속_법정동_코드", "부속_대지_구분_코드", "부속_번", "부속_지")),
     ("plat_plc", NV("대지_위치", 300)), ("atch_gb_cd", V("부속_대장_구분_코드", 2))] + 끝),
 "bld_expos": ("hub.t0309", SCD("expos_sk") + [("mgm_bldrgst_pk", PK)] + 지번 + [("new_plat_plc", NV("도로명_대지_위치", 300)), ("bld_nm", NV("건물_명", 200)),
     ("dong_nm", NV("동_명", 100)), ("ho_nm", NV("호_명", 100)), ("flr_gb_cd", V("층_구분_코드", 2)), ("flr_gb_nm", NV("층_구분_코드_명", 40)), ("flr_no", I("층_번호"))]
     + 대장 + [x for x in 도로 if x[0] != "new_plat_plc"] + 끝),
 "bld_jijigu": ("hub.t0310", SCD("jijigu_sk") + [("mgm_bldrgst_pk", PK)] + 지번 + [("new_plat_plc", NV("도로명_대지_위치", 400))] + 특수
     + [("jijigu_gb_cd", V("지역지구구역_구분_코드", 4)), ("jijigu_gb_nm", NV("지역지구구역_구분_코드_명", 40)), ("jijigu_cd", V("지역지구구역_코드", 20)),
        ("jijigu_nm", NV("지역지구구역_코드_명", 100)), ("repr_yn", V("대표_여부", 1)), ("etc_jijigu", NV("기타_지역지구구역", 200))] + 끝),
}

def plain(name, src, cols):
    body = ",\n       ".join(f"{expr} AS [{c}]" for c, expr in cols)
    return f"CREATE OR ALTER VIEW hubv.{name} AS\nSELECT {body}\n  FROM {src}\n WHERE [마지막월] IS NULL;\nGO\n"

# 합치는 두 표: 안쪽에서 칸을 바꾸고 바깥에서 자연키로 묶는다
FLR_IN = [("mgm_bldrgst_pk", PK), ("flr_gb_cd", V("층_구분_코드", 2)), ("flr_gb_nm", NV("층_구분_코드_명", 40)), ("flr_no", I("층_번호")), ("flr_no_nm", NV("층_번호_명", 40))] \
         + 구조 + 용도 + [("area", D("면적", 19, 5)), ("area_excl_yn", V("면적_제외_여부", 1)), ("dong_nm", NV("동_명", 100)), ("bld_nm", NV("건물_명", 200)),
         ("main_atch_gb_cd", V("주_부속_구분_코드", 2)), ("main_atch_gb_nm", NV("주_부속_구분_코드_명", 40))] + 끝 + [("처음월", "[처음월]"), ("행_sk", "[행_sk]")]
FLR_KEY = ["mgm_bldrgst_pk", "flr_gb_cd", "flr_no", "main_purps_cd", "strct_cd", "main_atch_gb_cd"]
AREA_IN = [("mgm_bldrgst_pk", PK), ("dong_nm", NV("동_명", 100)), ("ho_nm", NV("호_명", 100)), ("flr_gb_cd", V("층_구분_코드", 2)), ("flr_no", I("층_번호")),
           ("expos_pubuse_gb_cd", V("전유_공용_구분_코드", 2)), ("main_atch_gb_cd", V("주_부속_구분_코드", 2))] + 구조 + 용도 + [("area", D("면적", 19, 5))] + 끝 \
          + [("sigungu_cd", C("시군구_코드", 5)), ("bjdong_cd", C("법정동_코드", 5)), ("plat_gb_cd", V("대지_구분_코드", 1)), ("bun", V("번", 10)), ("ji", V("지", 10)),
             ("bld_nm", NV("건물_명", 200)), ("plat_plc", NV("대지_위치", 300)), ("regstr_gb_cd", V("대장_구분_코드", 2)), ("regstr_kind_cd", V("대장_종류_코드", 2)),
             ("pnu", PNU("시군구_코드", "법정동_코드", "대지_구분_코드", "번", "지"))]
AREA_KEY = ["mgm_bldrgst_pk", "expos_pubuse_gb_cd", "main_atch_gb_cd", "flr_gb_cd", "flr_no", "main_purps_cd", "strct_cd"]

def merged(name, src, inner, key, sk, where, 처음):
    ins = ",\n         ".join(f"{expr} AS [{c}]" for c, expr in inner)
    outs = []
    for c, _ in inner:
        if c in ("처음월", "행_sk"): continue
        if c in key: outs.append(f"x.[{c}]")
        elif c == "area": outs.append("CAST(SUM(x.area) AS DECIMAL(19, 5)) AS area")
        else: outs.append(f"MIN(x.[{c}]) AS [{c}]")
    outs += [f"MIN(x.[행_sk]) AS [{sk}]", "CAST(COUNT(*) AS INT) AS seg_cnt", "CAST(NULL AS BINARY(32)) AS row_hash", "CAST(NULL AS BIGINT) AS src_run_id",
             f"{처음} AS valid_from", "CAST('9999-12-31' AS DATETIME2(0)) AS valid_to", "CAST(1 AS BIT) AS is_current"]
    return (f"CREATE OR ALTER VIEW hubv.{name} AS\nSELECT " + ",\n       ".join(outs) +
            f"\n  FROM (SELECT {ins}\n          FROM {src}{where}) x\n GROUP BY " + ", ".join(f"x.[{c}]" for c in key) + ";\nGO\n")

out = ["/* 353 hubv — 허브 대장 위의 '우리 대장 표 모양' 뷰 (hub_views.py 가 만든다 · 손으로 고치지 말 것) */\n",
       "IF SCHEMA_ID('hubv') IS NULL EXEC('CREATE SCHEMA hubv');\nGO\n"]
for n, (src, cols) in VIEWS.items(): out.append(plain(n, src, cols))
# 층별개요는 hub.l0304(줄 그대로 — 같은 칸의 구획도 다 있음)에서
FLR_IN = [x for x in FLR_IN if x[0] not in ("처음월", "행_sk")] + [("처음월", "CAST(NULL AS CHAR(6))"), ("행_sk", "CAST(NULL AS BIGINT)")]
out.append(merged("bld_flr_outline", "hub.l0304", FLR_IN, FLR_KEY, "flr_sk", "", "CAST((SELECT MAX(넣은때) FROM hub.latest_done WHERE code = '0304') AS DATETIME2(0))"))
out.append(merged("bld_expos_pubuse_area", "hub.l0306", AREA_IN + [("행_sk", "CAST(NULL AS BIGINT)")], AREA_KEY, "expos_sk", "",
                  "CAST((SELECT MAX(넣은때) FROM hub.latest_done WHERE code = '0306') AS DATETIME2(0))"))
# 공동주택가격: 한 줄 = (호, 기준일, 생성일) — API 키(mgm_bldrgst_pk, std_day, crtn_day) 와 같다
HS = [("mgm_bldrgst_pk", PK), ("std_day", C("기준_일자", 8)), ("hsprc", f"TRY_CONVERT(DECIMAL(19, 0), {T('주택가격')})")] + \
     [x for x in 지번 if x[0] != "plat_plc"] + [("plat_plc", NV("대지_위치", 300)), ("bld_nm", NV("건물_명", 200)),
     ("regstr_gb_cd", V("대장_구분_코드", 2)), ("regstr_kind_cd", V("대장_종류_코드", 2))] + 끝 + \
     [("hsprc_sk", "CAST(NULL AS BIGINT)"), ("row_hash", "CAST(NULL AS BINARY(32))"), ("src_run_id", "CAST(NULL AS BIGINT)"),
      ("valid_from", "CAST((SELECT MAX(넣은때) FROM hub.latest_done WHERE code = '0308') AS DATETIME2(0))"),
      ("valid_to", "CAST('9999-12-31' AS DATETIME2(0))"), ("is_current", "CAST(1 AS BIT)")]
out.append("CREATE OR ALTER VIEW hubv.bld_hsprc AS\nSELECT " + ",\n       ".join(f"{e} AS [{c}]" for c, e in HS) + "\n  FROM hub.l0308;\nGO\n")
print("".join(out))
