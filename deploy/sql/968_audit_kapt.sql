/* 968 — K-apt 안 이어진 것 중 '필지에 세대 단지 하나' 의 속사정(읽기만) */
SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
IF OBJECT_ID('tempdb..#k') IS NOT NULL DROP TABLE #k;
SELECT k.kapt_code, k.kapt_name, k.pnu, k.kapt_usedate, kapt세대 = ISNULL(k.hhld_cnt, k.ho_cnt), k.ho_cnt,
       cid = (SELECT TOP 1 c.complex_id FROM gold.complex_pnu cp JOIN gold.complex c ON c.complex_id = cp.complex_id AND c.is_active = 1 AND c.hhld_cnt_sum > 0 WHERE cp.pnu = k.pnu),
       n세대단지 = (SELECT COUNT(DISTINCT cp.complex_id) FROM gold.complex_pnu cp JOIN gold.complex c ON c.complex_id = cp.complex_id AND c.is_active = 1 AND c.hhld_cnt_sum > 0 WHERE cp.pnu = k.pnu),
       같은필지kapt = (SELECT COUNT(*) FROM silver.kapt_complex k2 WHERE k2.is_current = 1 AND k2.pnu = k.pnu)
  INTO #k FROM silver.kapt_complex k
 WHERE k.is_current = 1 AND k.bjd_code LIKE '11%' AND NOT EXISTS (SELECT 1 FROM gold.complex_kapt x WHERE x.kapt_code = k.kapt_code);
DELETE FROM #k WHERE n세대단지 <> 1;
SELECT k.*, 대장세대 = c.hhld_cnt_sum, c.complex_nm, c.oldest_use_apr, c.latest_use_apr, c.dong_cnt, c.pnu_cnt,
       이미 = (SELECT TOP 1 x.kapt_name FROM gold.complex_kapt x WHERE x.complex_id = k.cid),
       세대차 = CASE WHEN ABS(k.kapt세대 - c.hhld_cnt_sum) * 1.0 / c.hhld_cnt_sum <= 0.05 THEN '5%안' WHEN ABS(k.kapt세대 - c.hhld_cnt_sum) * 1.0 / c.hhld_cnt_sum <= 0.2 THEN '20%안' ELSE '20%넘' END,
       날짜 = CASE WHEN k.kapt_usedate = c.oldest_use_apr THEN '처음동' WHEN k.kapt_usedate = c.latest_use_apr THEN '끝동' ELSE '다름' END
  INTO #k2 FROM #k k JOIN gold.complex c ON c.complex_id = k.cid;
SELECT (SELECT
  묶음 = (SELECT 이미있음 = CASE WHEN 이미 IS NULL THEN 0 ELSE 1 END, 같은필지kapt = CASE WHEN 같은필지kapt >= 2 THEN 2 ELSE 1 END, 세대차, 날짜, n = COUNT(*)
            FROM #k2 GROUP BY CASE WHEN 이미 IS NULL THEN 0 ELSE 1 END, CASE WHEN 같은필지kapt >= 2 THEN 2 ELSE 1 END, 세대차, 날짜 ORDER BY COUNT(*) DESC FOR JSON PATH),
  보기 = (SELECT TOP 30 kapt_name, kapt_usedate, kapt세대, cid, complex_nm, 대장세대, oldest_use_apr, latest_use_apr, dong_cnt, pnu_cnt, 이미, 같은필지kapt FROM #k2 ORDER BY kapt세대 DESC FOR JSON PATH)
  FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS j;
