SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* 국토부가 한 필지에 단지를 둘 이상으로 본 곳(aptSeq 마다 30건 이상) */
IF OBJECT_ID('tempdb..#ms') IS NOT NULL DROP TABLE #ms;
SELECT match_pnu pnu, apt_seq, n = COUNT(*), by_ = MIN(build_year) INTO #ms FROM silver.rtms_trade
 WHERE trade_kind LIKE 'APT%' AND trade_kind NOT LIKE 'SILV%' AND apt_seq IS NOT NULL AND match_pnu IS NOT NULL
 GROUP BY match_pnu, apt_seq HAVING COUNT(*) >= 30;
IF OBJECT_ID('tempdb..#mp') IS NOT NULL DROP TABLE #mp;
SELECT pnu, 국토부단지 = COUNT(*) INTO #mp FROM #ms GROUP BY pnu HAVING COUNT(*) > 1;
/* 그 필지의 우리 세대 단지와 대장 칸 */
IF OBJECT_ID('tempdb..#x') IS NOT NULL DROP TABLE #x;
SELECT m.pnu, cp.complex_id, t.pms_day, road = CASE WHEN t.na_road_cd IS NOT NULL AND TRY_CAST(t.na_main_bun AS INT) > 0 THEN CONCAT(t.na_road_cd, '-', TRY_CAST(t.na_main_bun AS INT)) END
  INTO #x FROM #mp m JOIN gold.complex_pnu cp ON cp.pnu = m.pnu
  JOIN gold.complex c ON c.complex_id = cp.complex_id AND c.merged_into IS NULL AND c.hhld_cnt_sum > 0
  JOIN gold.complex_bld cb ON cb.complex_id = cp.complex_id
  JOIN silver.bld_title t ON t.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND t.is_current = 1 AND t.main_purps_nm LIKE N'%주택%';
/* 묶음 = 허가일이 같거나 도로명이 같은 것끼리 이어진 덩어리 — 두 번 퍼뜨려 근사 */
IF OBJECT_ID('tempdb..#g') IS NOT NULL DROP TABLE #g;
SELECT DISTINCT pnu, complex_id, grp = complex_id INTO #g FROM #x;
DECLARE @i INT = 0;
WHILE @i < 6
BEGIN
  UPDATE g SET grp = z.m FROM #g g JOIN (
    SELECT a.pnu, a.complex_id, m = MIN(gb.grp) FROM #x a JOIN #x b ON b.pnu = a.pnu AND (b.pms_day = a.pms_day AND LEN(a.pms_day) = 8 OR b.road = a.road)
      JOIN #g gb ON gb.pnu = b.pnu AND gb.complex_id = b.complex_id GROUP BY a.pnu, a.complex_id) z ON z.pnu = g.pnu AND z.complex_id = g.complex_id
   WHERE z.m < g.grp;
  SET @i += 1;
END
SELECT 국토부여럿필지 = COUNT(*),
       우리단지하나뿐 = SUM(CASE WHEN 우리 = 1 THEN 1 ELSE 0 END),
       규칙후_하나로뭉침 = SUM(CASE WHEN 우리 > 1 AND 묶음 = 1 THEN 1 ELSE 0 END),
       규칙후_묶음수_국토부이상 = SUM(CASE WHEN 우리 > 1 AND 묶음 >= 국토부단지 THEN 1 ELSE 0 END),
       규칙후_묶음수_국토부미만_둘이상 = SUM(CASE WHEN 우리 > 1 AND 묶음 > 1 AND 묶음 < 국토부단지 THEN 1 ELSE 0 END)
  FROM (SELECT m.pnu, m.국토부단지, 우리 = (SELECT COUNT(DISTINCT complex_id) FROM #g g WHERE g.pnu = m.pnu), 묶음 = (SELECT COUNT(DISTINCT grp) FROM #g g WHERE g.pnu = m.pnu)
          FROM #mp m) z;
SELECT TOP 12 m.pnu, m.국토부단지, 국토부 = (SELECT STRING_AGG(CONCAT(s.apt_seq, '(', s.n, '건 ', s.by_, ')'), ' ') FROM #ms s WHERE s.pnu = m.pnu),
       우리 = (SELECT STRING_AGG(CONCAT(c.complex_id, ':', c.complex_nm, '[묶음', g.grp % 1000, ']'), ' / ') FROM #g g JOIN gold.complex c ON c.complex_id = g.complex_id WHERE g.pnu = m.pnu)
  FROM #mp m WHERE (SELECT COUNT(DISTINCT grp) FROM #g g WHERE g.pnu = m.pnu) = 1 AND (SELECT COUNT(DISTINCT complex_id) FROM #g g WHERE g.pnu = m.pnu) > 1
 ORDER BY m.국토부단지 DESC;
