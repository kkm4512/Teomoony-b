USE Teomoony;
GO
SET NOCOUNT ON;
GO
PRINT '--- 은평/성북/종로 대규모 허가 (아파트급) ---';
SELECT TOP 15 a.mgm_pmsrgst_pk, a.sigungu_cd, a.bjdong_cd, a.bld_nm,
       a.hhld_cnt, a.main_bld_cnt, a.arch_gb_nm, a.arch_pms_day, a.use_apr_day, a.pnu,
       단지붙음 = CASE WHEN EXISTS (SELECT 1 FROM gold.complex_pnu cp WHERE cp.pnu=a.pnu)
                       THEN N'Y' ELSE N'N' END
  FROM silver.arch_permit a
 WHERE a.is_current = 1 AND a.hhld_cnt >= 300
 ORDER BY a.hhld_cnt DESC;
GO
