/* 238_pmsdong_probe : 동별 건축허가가 실제로 뭘 들고 있나 (2026-10-21) 읽기만.
   ★ 화면을 설계하기 전에 **채워진 비율**을 본다. 빈 칸을 표에 넣으면 소음이다. */
USE Teomoony;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 전체 = COUNT(*),
  동명 = SUM(CASE WHEN NULLIF(bld_nm,'')      IS NOT NULL THEN 1 ELSE 0 END),
  주부속 = SUM(CASE WHEN NULLIF(main_atch_gb_nm,'') IS NOT NULL THEN 1 ELSE 0 END),
  주용도 = SUM(CASE WHEN NULLIF(main_purps_nm,'') IS NOT NULL THEN 1 ELSE 0 END),
  구조 = SUM(CASE WHEN NULLIF(strct_nm,'')    IS NOT NULL THEN 1 ELSE 0 END),
  지붕 = SUM(CASE WHEN NULLIF(roof_nm,'')     IS NOT NULL THEN 1 ELSE 0 END),
  건축면적 = SUM(CASE WHEN arch_area > 0 THEN 1 ELSE 0 END),
  연면적 = SUM(CASE WHEN tot_area > 0 THEN 1 ELSE 0 END),
  세대 = SUM(CASE WHEN hhld_cnt > 0 THEN 1 ELSE 0 END),
  호 = SUM(CASE WHEN ho_cnt > 0 THEN 1 ELSE 0 END),
  승강기 = SUM(CASE WHEN ride_use_elvt_cnt > 0 THEN 1 ELSE 0 END),
  허가연결 = SUM(CASE WHEN NULLIF(mgm_pmsrgst_pk,'') IS NOT NULL THEN 1 ELSE 0 END)
FROM silver.arch_permit_dong WHERE is_current = 1;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
PRINT '--- 허가 하나에 동이 몇 개나 ---';
SELECT 허가수 = COUNT(*), 동합 = SUM(n), 최대 = MAX(n),
       평균 = CAST(AVG(CAST(n AS FLOAT)) AS DECIMAL(6,2))
  FROM (SELECT mgm_pmsrgst_pk, n = COUNT(*) FROM silver.arch_permit_dong
         WHERE is_current = 1 AND mgm_pmsrgst_pk IS NOT NULL
         GROUP BY mgm_pmsrgst_pk) q;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
PRINT '--- 보기 한 줄 ---';
SELECT TOP 3 bld_nm, main_atch_gb_nm, main_purps_nm, strct_nm, roof_nm,
       arch_area, tot_area, hhld_cnt, ho_cnt, ride_use_elvt_cnt
  FROM silver.arch_permit_dong WHERE is_current = 1 AND hhld_cnt > 0;
GO
