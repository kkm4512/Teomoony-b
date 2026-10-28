# -*- coding: utf-8 -*-
"""hub_views_closed - 허브 폐쇄말소대장(hub.t0403 표제부 · hub.t0402 총괄표제부) 위에 우리 폐쇄 표(silver.bld_closed_title · bld_closed_recap)와 같은 모양의 뷰
  (2026-10-28 사장님 "3 너가받아" — 폐쇄대장은 API 로 서울 · 경기 일부 35만 건 · 허브 9월 전국 파일 234만 건)
  py hub_views_closed.py > ..\\deploy\\sql\\380_hub_views_closed.sql
  ★ 값 바꾸기는 load_closed_bld.py(API 적재)와 **글자 그대로** 같다: s = 앞뒤 빈칸 자름 · 빈 글자 NULL / n = 숫자(쉼표 뗌) · **원문 0 = 안 적음 → NULL** ·
    정수 칸은 반올림 / d8 = 숫자 8자리일 때만. PNU = meta.fn_make_pnu 와 같은 식."""
def S(c): return f"NULLIF(LTRIM(RTRIM([{c}])), N'')"
def SV(c, n): return f"CAST({S(c)} AS VARCHAR({n}))"
def SN(c, n): return f"CAST({S(c)} AS NVARCHAR({n}))"
def SC(c, n): return f"CAST({S(c)} AS CHAR({n}))"
def N(c, p, s): return f"CAST(NULLIF(TRY_CONVERT(FLOAT, REPLACE({S(c)}, N',', N'')), 0) AS DECIMAL({p}, {s}))"
def NI(c): return f"CAST(ROUND(NULLIF(TRY_CONVERT(FLOAT, REPLACE({S(c)}, N',', N'')), 0), 0) AS INT)"
def D8(c): return f"CAST(CASE WHEN {S(c)} LIKE N'[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' THEN {S(c)} END AS CHAR(8))"
def PNU(sg, bj, gb, b, j):
    sg_, bj_, b_, j_ = S(sg), S(bj), S(b), S(j)
    return (f"CASE WHEN LEN({sg_}) = 5 AND LEN({bj_}) = 5 AND ({b_} IS NULL OR TRY_CAST({b_} AS INT) IS NOT NULL) AND ({j_} IS NULL OR TRY_CAST({j_} AS INT) IS NOT NULL) "
            f"THEN CAST({sg_} + {bj_} + CASE LTRIM(RTRIM(ISNULL([{gb}], N'0'))) WHEN N'1' THEN N'2' ELSE N'1' END "
            f"+ RIGHT(N'0000' + CAST(ISNULL(TRY_CAST({b_} AS INT), 0) AS NVARCHAR(10)), 4) + RIGHT(N'0000' + CAST(ISNULL(TRY_CAST({j_} AS INT), 0) AS NVARCHAR(10)), 4) AS CHAR(19)) END")
머리 = [("mgm_shtreg_pk", SV("관리_폐쇄말소대장_PK", 30)), ("shter_gb_cd", SV("폐쇄말소_구분_코드", 2)), ("shter_gb_nm", SN("폐쇄말소_구분_코드_명", 20)),
        ("shter_day", D8("폐쇄말소_일")), ("regstr_gb_nm", SN("대장_구분_코드_명", 20))]
지번 = [("sigungu_cd", SC("시군구_코드", 5)), ("bjdong_cd", SC("법정동_코드", 5)), ("plat_gb_cd", SV("대지_구분_코드", 1)), ("bun", SV("번", 10)), ("ji", SV("지", 10)),
        ("pnu", PNU("시군구_코드", "법정동_코드", "대지_구분_코드", "번", "지")), ("plat_plc", SN("대지_위치", 300)), ("new_plat_plc", SN("도로명_대지_위치", 300)),
        ("bld_nm", SN("건물_명", 200))]
면적 = [("plat_area", N("대지_면적", 19, 5)), ("arch_area", N("건축_면적", 19, 5)), ("bc_rat", N("건폐_율", 19, 5)), ("tot_area", N("연면적", 19, 5)), ("vl_rat", N("용적_률", 19, 5))]
끝 = [("loaded_at", "CAST(SYSDATETIME() AS DATETIME2(0))")]
VIEWS = {
 "bld_closed_title": ("hub.t0403", 머리 + [("regstr_kind_nm", SN("대장_종류_코드_명", 20))] + 지번 + [("dong_nm", SN("동_명", 100)), ("main_atch_gb_nm", SN("주_부속_구분_코드_명", 20))]
     + 면적 + [("strct_nm", SN("구조_코드_명", 100)), ("main_purps_cd", SV("주_용도_코드", 10)), ("main_purps_nm", SN("주_용도_코드_명", 100)), ("etc_purps", SN("기타_용도", 400)),
               ("hhld_cnt", NI("세대_수")), ("fmly_cnt", NI("가구_수")), ("ho_cnt", NI("호_수")), ("heit", N("높이", 19, 3)), ("grnd_flr_cnt", NI("지상_층_수")),
               ("ugrnd_flr_cnt", NI("지하_층_수")), ("use_apr_day", D8("사용승인_일")), ("pms_day", D8("허가_일")), ("stcns_day", D8("착공_일")), ("crtn_day", D8("생성_일자"))] + 끝),
 "bld_closed_recap": ("hub.t0402", 머리 + [("new_old_regstr_gb_nm", SN("신_구_대장_구분_코드_명", 20))] + 지번 + 면적
     + [("main_purps_nm", SN("주_용도_코드_명", 100)), ("main_bld_cnt", NI("주_건축물_수")), ("atch_bld_cnt", NI("부속_건축물_수")), ("hhld_cnt", NI("세대_수")),
        ("fmly_cnt", NI("가구_수")), ("ho_cnt", NI("호_수")), ("tot_pkng_cnt", NI("총_주차_수")), ("use_apr_day", D8("사용승인_일")), ("pms_day", D8("허가_일")), ("crtn_day", D8("생성_일자"))] + 끝),
}
out = ["/* 380 hubv 폐쇄대장 — 허브 폐쇄말소대장 위의 '우리 폐쇄 표 모양' 뷰 (hub_views_closed.py 가 만든다 · 손으로 고치지 말 것) */\n",
       "IF SCHEMA_ID('hubv') IS NULL EXEC('CREATE SCHEMA hubv');\nGO\n"]
for n, (src, cols) in VIEWS.items():
    body = ",\n       ".join(f"{e} AS [{c}]" for c, e in cols)
    out.append(f"CREATE OR ALTER VIEW hubv.{n} AS\nSELECT {body}\n  FROM {src}\n WHERE [마지막월] IS NULL AND {S('관리_폐쇄말소대장_PK')} IS NOT NULL;\nGO\n")
if __name__ == "__main__":
    import sys; sys.stdout.reconfigure(encoding="utf-8"); print("".join(out))
