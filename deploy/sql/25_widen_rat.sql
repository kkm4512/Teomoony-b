SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* ============================================================
   25_widen_rat : 건폐율·용적률 컬럼 확장 (2026-10-16)

   정릉동 표제부 적재가 18페이지에서 통째로 죽었다.

     정릉동 258-37   bcRat = 59315      <- 건폐율 59,315%
     bc_rat          DECIMAL(9,5)       <- 정수부 4자리, 최대 9,999
     -> Arithmetic overflow. run 전체가 FAIL.

   **59,315% 는 데이터 오류다.** 건폐율은 정의상 100% 를 넘을 수 없다
   (대지면적 대비 건축면적). 대장에 소수점이 빠져 들어간 것으로 보인다.

   그래도 **버리지 않고 넓힌다.** 이 프로젝트 1원칙이 "원본을 버리지 않는다" 이고,
   이상한 값은 버리는 것이 아니라 **이상하다고 표시**해 왔다
   (v_rtms_gap, 장충_잔액_상태, 주차 총계 vs 내역 합, 승강기 승용 0).
   NULL 로 바꾸면 "대장에 값이 없다" 와 구분이 사라진다 — 오늘 내내 경계한 바로 그것.

   화면이 `건폐율 > 100%` 를 "대장 값 이상" 으로 표시한다.

   ★ 확장은 **무손실**이다. scale 을 줄이지 않는다(9,5 -> 14,5 / 9,4 -> 14,5).
     용적률은 정상 범위에서도 1,000% 를 넘는다(고밀 주상복합). 4자리는 원래 좁았다.
   ============================================================ */
USE Teomoony;
GO

ALTER TABLE silver.bld_title       ALTER COLUMN bc_rat DECIMAL(14,5) NULL;
ALTER TABLE silver.bld_title       ALTER COLUMN vl_rat DECIMAL(14,5) NULL;
GO
ALTER TABLE silver.bld_recap_title ALTER COLUMN bc_rat DECIMAL(14,5) NULL;
ALTER TABLE silver.bld_recap_title ALTER COLUMN vl_rat DECIMAL(14,5) NULL;
GO
ALTER TABLE silver.arch_permit     ALTER COLUMN bc_rat DECIMAL(14,5) NULL;
ALTER TABLE silver.arch_permit     ALTER COLUMN vl_rat DECIMAL(14,5) NULL;
GO

/* 좌표 컬럼(centroid_*, bbox_*)은 그대로 둔다 — 위도 ±90 / 경도 ±180 이라
   정수부 3~5자리면 충분하다. 넓힐 이유가 없다. */

/* ---------- 이상치 점검 ----------
   적재 후 한 번 돌려보는 용도. 건폐율 100 초과 / 용적률 2000 초과를 센다. */
PRINT '--- 건폐율 100% 초과 ---';
SELECT 출처='표제부', sigungu_cd, bjdong_cd, bun, ji, mgm_bldrgst_pk, bc_rat
FROM silver.bld_title WHERE is_current=1 AND bc_rat > 100
UNION ALL
SELECT '총괄', sigungu_cd, bjdong_cd, bun, ji, mgm_bldrgst_pk, bc_rat
FROM silver.bld_recap_title WHERE is_current=1 AND bc_rat > 100;
GO

PRINT '25_widen_rat done.';
GO
