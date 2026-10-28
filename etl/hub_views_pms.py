# -*- coding: utf-8 -*-
"""hub_views_pms - 허브 건축인허가(hub.t0101 기본개요 · hub.t0102 동별개요) 위에 우리 인허가 표(silver.arch_permit · arch_permit_dong)와 같은 모양의 뷰
  (2026-10-28 사장님 "3 너가받아" — 인허가는 API 로 서울 · 대구 · 경기 일부 62만 건뿐 · 허브 9월 전국 파일 655만 건이 이미 들어와 있다)
  py hub_views_pms.py > ..\\deploy\\sql\\379_hub_views_pms.sql
  ★ 값 바꾸기는 hub_views.py(대장)와 같다 — 앞뒤 빈칸 자름 · 빈 글자 = NULL · 정수는 int(float) · 소수는 그 칸의 decimal · PNU = fn_make_pnu 와 같은 식.
  ★ 지금 줄 = 허브 마지막월 IS NULL. valid_from = 처음월 1일. src = 'HUB_0101' / 'HUB_0102'(API 는 ARCHPMS_BASIS)."""
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
지번 = [("pnu", PNU("시군구_코드", "법정동_코드", "대지_구분_코드", "번", "지")), ("sigungu_cd", C("시군구_코드", 5)), ("bjdong_cd", C("법정동_코드", 5)),
        ("plat_gb_cd", V("대지_구분_코드", 1)), ("bun", V("번", 10)), ("ji", V("지", 10)), ("plat_plc", NV("대지_위치", 300)), ("bld_nm", NV("건물_명", 200))]
SCD = lambda src: [("src", f"CAST('{src}' AS VARCHAR(30))"), ("row_hash", "[행해시]"), ("src_run_id", "CAST(NULL AS BIGINT)"),
                   ("valid_from", "CAST(CAST([처음월] + '01' AS DATE) AS DATETIME2(0))"), ("valid_to", "CAST('9999-12-31' AS DATETIME2(0))"), ("is_current", "CAST(1 AS BIT)")]
VIEWS = {
 "arch_permit": ("hub.t0101", [("mgm_pmsrgst_pk", V("관리_허가대장_PK", 50))] + 지번 + [
     ("splot_nm", NV("특수지_명", 100)), ("block", NV("블록", 40)), ("lot", NV("로트", 40)),
     ("jimok_cd", V("지목_코드", 10)), ("jimok_nm", NV("지목_코드_명", 40)), ("jiyuk_cd", V("지역_코드", 10)), ("jiyuk_nm", NV("지역_코드_명", 80)),
     ("jigu_cd", V("지구_코드", 10)), ("jigu_nm", NV("지구_코드_명", 80)), ("guyuk_cd", V("구역_코드", 10)), ("guyuk_nm", NV("구역_코드_명", 80)),
     ("arch_gb_cd", V("건축_구분_코드", 10)), ("arch_gb_nm", NV("건축_구분_코드_명", 40)), ("main_purps_cd", V("주_용도_코드", 10)), ("main_purps_nm", NV("주_용도_코드_명", 80)),
     ("plat_area", D("대지_면적", 18, 4)), ("arch_area", D("건축_면적", 18, 4)), ("bc_rat", D("건폐_율", 14, 5)), ("tot_area", D("연면적", 18, 4)),
     ("vl_rat_estm_tot_area", D("용적_률_산정_연면적", 18, 4)), ("vl_rat", D("용적_률", 14, 5)),
     ("main_bld_cnt", I("주_건축물_수")), ("atch_bld_dong_cnt", I("부속_건축물_동_수")), ("hhld_cnt", I("세대_수")), ("ho_cnt", I("호_수")), ("fmly_cnt", I("가구_수")),
     ("tot_pkng_cnt", I("총_주차_수")), ("arch_pms_day", C("건축_허가_일", 8)), ("stcns_sched_day", C("착공_예정_일", 8)), ("real_stcns_day", C("실제_착공_일", 8)),
     ("stcns_delay_day", C("착공_연기_일", 8)), ("use_apr_day", C("사용승인_일", 8)), ("crtn_day", C("생성_일자", 8))] + SCD("HUB_0101")),
 "arch_permit_dong": ("hub.t0102", [("mgm_dong_ouln_pk", V("관리_동별_개요_PK", 50)), ("mgm_pmsrgst_pk", V("관리_허가대장_PK", 50))] + 지번 + [
     ("main_atch_gb_cd", V("주_부속_구분_코드", 10)), ("main_atch_gb_nm", NV("주_부속_구분_코드_명", 40)), ("main_purps_cd", V("주_용도_코드", 10)), ("main_purps_nm", NV("주_용도_코드_명", 80)),
     ("strct_cd", V("구조_코드", 10)), ("strct_nm", NV("구조_코드_명", 80)), ("roof_cd", V("지붕_코드", 10)), ("roof_nm", NV("지붕_코드_명", 80)),
     ("arch_area", D("건축_면적", 18, 4)), ("tot_area", D("연면적", 18, 4)), ("vl_rat_estm_tot_area", D("용적_률_산정_연면적", 18, 4)),
     ("hhld_cnt", I("세대_수")), ("ho_cnt", I("호_수")), ("fmly_cnt", I("가구_수")), ("ride_use_elvt_cnt", I("승용_승강기_수")), ("emgen_use_elvt_cnt", I("비상용_승강기_수")),
     ("crtn_day", C("생성_일자", 8))] + SCD("HUB_0102")),
}
out = ["/* 379 hubv 인허가 — 허브 건축인허가 위의 '우리 인허가 표 모양' 뷰 (hub_views_pms.py 가 만든다 · 손으로 고치지 말 것) */\n",
       "IF SCHEMA_ID('hubv') IS NULL EXEC('CREATE SCHEMA hubv');\nGO\n"]
for n, (src, cols) in VIEWS.items():
    body = ",\n       ".join(f"{e} AS [{c}]" for c, e in cols)
    out.append(f"CREATE OR ALTER VIEW hubv.{n} AS\nSELECT {body}\n  FROM {src}\n WHERE [마지막월] IS NULL;\nGO\n")
if __name__ == "__main__":
    import sys; sys.stdout.reconfigure(encoding="utf-8"); print("".join(out))
