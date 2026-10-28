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
SELECT 여럿필지 = (SELECT COUNT(*) FROM (SELECT pnu FROM gold.complex_pnu GROUP BY pnu HAVING COUNT(*) > 1) z),
       세대있는단지둘이상필지 = (SELECT COUNT(*) FROM #amb);
SELECT 종류 = LEFT(t.trade_kind, 3), 이어진거래 = COUNT_BIG(*),
       애매필지거래 = SUM(CASE WHEN a.pnu IS NOT NULL THEN 1 ELSE 0 END)
  FROM silver.rtms_trade t LEFT JOIN #amb a ON a.pnu = t.match_pnu
 WHERE t.match_complex_id IS NOT NULL GROUP BY LEFT(t.trade_kind, 3);
SELECT TOP 15 a.pnu, a.단지, 거래 = (SELECT COUNT(*) FROM silver.rtms_trade t WHERE t.match_pnu = a.pnu AND t.match_complex_id IS NOT NULL),
       단지들 = (SELECT STRING_AGG(CONCAT(h.complex_id, ':', c.complex_nm, '(', h.hh, '세대 ', h.yr, ')'), ' / ') FROM #h h JOIN gold.complex c ON c.complex_id = h.complex_id WHERE h.pnu = a.pnu)
  FROM #amb a ORDER BY 3 DESC;
