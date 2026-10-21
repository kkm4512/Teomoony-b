/* 231_jijigu_where : 용도지역 행은 표제부에 붙나 총괄표제부에 붙나 (2026-10-20) 읽기만 */
USE Teomoony;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
WITH j AS (SELECT DISTINCT mgm_bldrgst_pk FROM silver.bld_jijigu
            WHERE is_current = 1 AND jijigu_gb_cd = '1' AND repr_yn = '1')
SELECT 지구pk = COUNT(*),
       표제부에있음 = SUM(CASE WHEN t.mgm_bldrgst_pk IS NULL THEN 0 ELSE 1 END),
       총괄에있음   = SUM(CASE WHEN r.mgm_bldrgst_pk IS NULL THEN 0 ELSE 1 END),
       어디에도없음 = SUM(CASE WHEN t.mgm_bldrgst_pk IS NULL AND r.mgm_bldrgst_pk IS NULL THEN 1 ELSE 0 END)
  FROM j
  LEFT JOIN (SELECT mgm_bldrgst_pk FROM silver.bld_title      WHERE is_current = 1) t ON t.mgm_bldrgst_pk = j.mgm_bldrgst_pk
  LEFT JOIN (SELECT mgm_bldrgst_pk FROM silver.bld_recap_title WHERE is_current = 1) r ON r.mgm_bldrgst_pk = j.mgm_bldrgst_pk;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
PRINT '--- 총괄표제부에 용적률이 있나 ---';
SELECT 총괄 = COUNT(*),
       용적률있음 = SUM(CASE WHEN vl_rat > 0 THEN 1 ELSE 0 END),
       대지면적있음 = SUM(CASE WHEN plat_area > 0 THEN 1 ELSE 0 END)
  FROM silver.bld_recap_title WHERE is_current = 1;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
PRINT '--- 총괄 중 용도지역까지 붙는 것 ---';
WITH j AS (SELECT DISTINCT mgm_bldrgst_pk FROM silver.bld_jijigu
            WHERE is_current = 1 AND jijigu_gb_cd = '1' AND repr_yn = '1')
SELECT 총괄_용적률있음 = COUNT(*)
  FROM silver.bld_recap_title r
  JOIN j ON j.mgm_bldrgst_pk = r.mgm_bldrgst_pk
 WHERE r.is_current = 1 AND r.vl_rat > 0;
GO
