/* 230_jijigu_probe : bld_jijigu 의 거르는 칸이 맞나 (2026-10-20) 읽기만 한다 */
USE Teomoony;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
PRINT '--- jijigu_gb_cd 값 분포 ---';
SELECT TOP 10 jijigu_gb_cd, 건수 = COUNT(*), 보기 = MIN(jijigu_nm)
  FROM silver.bld_jijigu WHERE is_current = 1
 GROUP BY jijigu_gb_cd ORDER BY COUNT(*) DESC;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
PRINT '--- repr_yn 값 분포 ---';
SELECT repr_yn, 건수 = COUNT(*) FROM silver.bld_jijigu WHERE is_current = 1
 GROUP BY repr_yn ORDER BY COUNT(*) DESC;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
PRINT '--- 도곡렉슬(507648) 동들이 bld_jijigu 에 있나 ---';
SELECT 동수 = COUNT(*),
       지구행있음 = SUM(CASE WHEN j.mgm_bldrgst_pk IS NULL THEN 0 ELSE 1 END)
  FROM gold.complex_bld cb
  LEFT JOIN (SELECT DISTINCT mgm_bldrgst_pk FROM silver.bld_jijigu WHERE is_current = 1) j
         ON j.mgm_bldrgst_pk = cb.mgm_bldrgst_pk
 WHERE cb.complex_id = 507648;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
PRINT '--- 도곡렉슬 동 하나의 지구 행 생김새 ---';
SELECT TOP 8 j.mgm_bldrgst_pk, j.jijigu_gb_cd, j.jijigu_cd, j.jijigu_nm, j.repr_yn
  FROM gold.complex_bld cb
  JOIN silver.bld_jijigu j ON j.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND j.is_current = 1
 WHERE cb.complex_id = 507648;
GO
