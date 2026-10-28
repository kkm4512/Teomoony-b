SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* 묶은 단지(374)의 종류: 대장 기타용도(etc_purps)로 */
IF OBJECT_ID('tempdb..#k') IS NOT NULL DROP TABLE #k;
SELECT m.new_id, 종류 = CASE WHEN MAX(CASE WHEN t.etc_purps LIKE N'%아파트%' THEN 1 ELSE 0 END) = 1 THEN N'아파트'
                             WHEN MAX(CASE WHEN t.etc_purps LIKE N'%연립%' THEN 1 ELSE 0 END) = 1 THEN N'연립'
                             WHEN MAX(CASE WHEN t.etc_purps LIKE N'%다세대%' THEN 1 ELSE 0 END) = 1 THEN N'다세대' ELSE N'모름' END,
       조각 = (SELECT COUNT(*) + 1 FROM ops.complex_merged x WHERE x.new_id = m.new_id AND x.근거 LIKE N'373%')
  INTO #k FROM (SELECT DISTINCT new_id FROM ops.complex_merged WHERE 근거 LIKE N'373%') m
  JOIN gold.complex_bld cb ON cb.complex_id = m.new_id
  JOIN silver.bld_title t ON t.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND t.is_current = 1 AND t.main_purps_nm = N'공동주택'
 GROUP BY m.new_id;
SELECT 종류, 단지 = COUNT(*), 조각 = SUM(조각) FROM #k GROUP BY 종류 ORDER BY 2 DESC;
/* 연립·다세대 검증: 묶인 조각들의 실거래(RH) 건축년도가 남는 단지의 사용승인 연도들과 맞나 · 같은 필지에 남은 다른 RH 단지 */
SELECT TOP 12 c.complex_id, c.complex_nm, k.종류, k.조각, c.dong_cnt, c.hhld_cnt_sum, c.trade_cnt, c.rent_cnt, c.rep_plat_plc
  FROM #k k JOIN gold.complex c ON c.complex_id = k.new_id WHERE k.종류 IN (N'연립', N'다세대') ORDER BY NEWID();
/* 아직 안 묶인 연립·다세대 조각: 같은 필지에 공동주택 단지가 2곳 이상 남은 필지 */
IF OBJECT_ID('tempdb..#r') IS NOT NULL DROP TABLE #r;
SELECT cp.pnu, cp.complex_id, 종류 = MAX(CASE WHEN t.etc_purps LIKE N'%아파트%' THEN N'아파트' WHEN t.etc_purps LIKE N'%연립%' THEN N'연립' WHEN t.etc_purps LIKE N'%다세대%' THEN N'다세대' ELSE N'모름' END),
       pms = MIN(t.pms_day), road = MIN(CONCAT(t.na_road_cd, '-', TRY_CAST(t.na_main_bun AS INT)))
  INTO #r FROM gold.complex_pnu cp JOIN gold.complex c ON c.complex_id = cp.complex_id AND c.merged_into IS NULL
  JOIN gold.complex_bld cb ON cb.complex_id = cp.complex_id
  JOIN silver.bld_title t ON t.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND t.is_current = 1 AND t.main_purps_nm = N'공동주택' AND t.hhld_cnt > 0
 GROUP BY cp.pnu, cp.complex_id;
SELECT 종류, 남은필지 = COUNT(DISTINCT pnu), 단지 = COUNT(*) FROM #r
 WHERE pnu IN (SELECT pnu FROM #r GROUP BY pnu HAVING COUNT(*) > 1) GROUP BY 종류;
SELECT TOP 10 r.pnu, 단지들 = STRING_AGG(CONCAT(c.complex_nm, '[', r.종류, ' 허가', r.pms, ' 도로', r.road, ']'), N' / ')
  FROM #r r JOIN gold.complex c ON c.complex_id = r.complex_id
 WHERE r.pnu IN (SELECT pnu FROM #r WHERE 종류 IN (N'연립', N'다세대') GROUP BY pnu HAVING COUNT(*) > 1)
 GROUP BY r.pnu ORDER BY NEWID();
