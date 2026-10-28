SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT STRING_AGG(name, ',') FROM sys.columns WHERE object_id = OBJECT_ID('silver.rtms_trade');
/* 필지마다 주택 세대가 있는 단지 수 */
IF OBJECT_ID('tempdb..#h') IS NOT NULL DROP TABLE #h;
SELECT cp.pnu, cp.complex_id, hh = SUM(ISNULL(t.hhld_cnt,0)), yr = MIN(LEFT(t.use_apr_day,4))
  INTO #h FROM gold.complex_pnu cp JOIN gold.complex c ON c.complex_id = cp.complex_id AND c.merged_into IS NULL
  JOIN gold.complex_bld cb ON cb.complex_id = cp.complex_id
  JOIN silver.bld_title t ON t.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND t.is_current = 1 AND t.main_purps_nm LIKE N'%주택%'
 WHERE cp.pnu IN (SELECT pnu FROM gold.complex_pnu GROUP BY pnu HAVING COUNT(*) > 1)
 GROUP BY cp.pnu, cp.complex_id HAVING SUM(ISNULL(t.hhld_cnt,0)) > 0;
IF OBJECT_ID('tempdb..#amb') IS NOT NULL DROP TABLE #amb;
SELECT pnu, 단지 = COUNT(*) INTO #amb FROM #h GROUP BY pnu HAVING COUNT(*) > 1;
CREATE CLUSTERED INDEX x ON #amb (pnu);
IF OBJECT_ID('tempdb..#t') IS NOT NULL DROP TABLE #t;
SELECT t.trade_sk, k = LEFT(t.trade_kind,3), t.match_pnu, t.match_complex_id, by_ = CAST(t.build_year AS VARCHAR(4))
  INTO #t FROM silver.rtms_trade t JOIN #amb a ON a.pnu = t.match_pnu WHERE t.match_complex_id IS NOT NULL AND t.trade_kind NOT LIKE 'OFFI%' AND t.trade_kind NOT LIKE 'NRG%';
IF OBJECT_ID('tempdb..#yc') IS NOT NULL DROP TABLE #yc;
SELECT pnu, yr, n = COUNT(*) INTO #yc FROM #h GROUP BY pnu, yr;
SELECT 거래 = COUNT(*),
       건축년도없음 = SUM(CASE WHEN t.by_ IS NULL OR t.by_ = '' THEN 1 ELSE 0 END),
       지금단지와_년도같음 = SUM(CASE WHEN h.yr = t.by_ THEN 1 ELSE 0 END),
       지금단지와_년도다름 = SUM(CASE WHEN h.yr <> t.by_ THEN 1 ELSE 0 END),
       다름_년도맞는후보하나 = SUM(CASE WHEN h.yr <> t.by_ AND y.n = 1 THEN 1 ELSE 0 END),
       다름_년도맞는후보여럿 = SUM(CASE WHEN h.yr <> t.by_ AND y.n > 1 THEN 1 ELSE 0 END),
       다름_년도맞는후보없음 = SUM(CASE WHEN h.yr <> t.by_ AND y.n IS NULL THEN 1 ELSE 0 END)
  FROM #t t LEFT JOIN #h h ON h.pnu = t.match_pnu AND h.complex_id = t.match_complex_id
  LEFT JOIN #yc y ON y.pnu = t.match_pnu AND y.yr = t.by_;
