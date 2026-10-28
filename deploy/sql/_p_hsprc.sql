SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT TOP 3 mgm_bldrgst_pk, std_day, pnu, bld_nm, regstr_gb_cd, regstr_kind_cd FROM silver.bld_hsprc;
IF OBJECT_ID('tempdb..#s') IS NOT NULL DROP TABLE #s;
SELECT TOP 200000 mgm_bldrgst_pk, pnu INTO #s FROM silver.bld_hsprc TABLESAMPLE (0.5 PERCENT) WHERE is_current = 1;
SELECT 표본 = COUNT(*),
  표제부PK = SUM(CASE WHEN t.mgm_bldrgst_pk IS NOT NULL THEN 1 ELSE 0 END),
  단지필지 = SUM(CASE WHEN cp.pnu IS NOT NULL THEN 1 ELSE 0 END)
  FROM #s s
  LEFT JOIN (SELECT DISTINCT mgm_bldrgst_pk FROM gold.complex_bld) t ON t.mgm_bldrgst_pk = s.mgm_bldrgst_pk
  LEFT JOIN (SELECT DISTINCT pnu FROM gold.complex_pnu) cp ON cp.pnu = s.pnu;
SELECT TOP 3 mgm_bldrgst_pk FROM silver.bld_title WHERE is_current = 1;
SELECT 최신 = MAX(std_day), 줄 = COUNT_BIG(*) FROM silver.bld_hsprc WHERE std_day = (SELECT MAX(std_day) FROM silver.bld_hsprc);
