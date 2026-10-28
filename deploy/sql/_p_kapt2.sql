SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
IF OBJECT_ID('tempdb..#u') IS NOT NULL DROP TABLE #u;
SELECT k.kapt_code, k.kapt_name, k.pnu, k.kapt_usedate, kh = COALESCE(NULLIF(k.hhld_cnt, 0), k.ho_cnt), k.doro_juso
  INTO #u FROM silver.kapt_complex k WHERE k.is_current = 1 AND NOT EXISTS (SELECT 1 FROM gold.complex_kapt ck WHERE ck.kapt_code = k.kapt_code)
   AND COALESCE(NULLIF(k.hhld_cnt, 0), k.ho_cnt) > 0;
/* 넷째 길 후보: K-apt 지번 = 단지 필지 · 사용승인일이 단지 범위 안 · 세대 */
IF OBJECT_ID('tempdb..#m') IS NOT NULL DROP TABLE #m;
SELECT u.kapt_code, c.complex_id, u.kh, c.hhld_cnt_sum, d = ABS(c.hhld_cnt_sum - u.kh) * 1.0 / u.kh
  INTO #m FROM #u u JOIN gold.complex_pnu cp ON cp.pnu = u.pnu
  JOIN gold.complex c ON c.complex_id = cp.complex_id AND c.is_active = 1 AND c.merged_into IS NULL AND c.hhld_cnt_sum > 0
 WHERE LEN(u.kapt_usedate) = 8 AND u.kapt_usedate BETWEEN c.oldest_use_apr AND ISNULL(c.latest_use_apr, c.oldest_use_apr)
   AND NOT EXISTS (SELECT 1 FROM gold.complex_kapt x WHERE x.complex_id = c.complex_id);
SELECT 기준 = N'세대 ±5%', 후보 = COUNT(DISTINCT kapt_code),
       하나씩 = (SELECT COUNT(*) FROM (SELECT kapt_code FROM #m m WHERE d <= 0.05 GROUP BY kapt_code HAVING COUNT(DISTINCT complex_id) = 1) a
                  WHERE NOT EXISTS (SELECT 1 FROM #m m2 JOIN #m m3 ON m3.complex_id = m2.complex_id AND m3.kapt_code <> m2.kapt_code AND m3.d <= 0.05 WHERE m2.kapt_code = a.kapt_code AND m2.d <= 0.05)),
       세대똑같음 = (SELECT COUNT(DISTINCT kapt_code) FROM #m WHERE d = 0)
  FROM #m WHERE d <= 0.05
UNION ALL
SELECT N'세대 ±20%', COUNT(DISTINCT kapt_code),
       (SELECT COUNT(*) FROM (SELECT kapt_code FROM #m m WHERE d <= 0.2 GROUP BY kapt_code HAVING COUNT(DISTINCT complex_id) = 1) a
         WHERE NOT EXISTS (SELECT 1 FROM #m m2 JOIN #m m3 ON m3.complex_id = m2.complex_id AND m3.kapt_code <> m2.kapt_code AND m3.d <= 0.2 WHERE m2.kapt_code = a.kapt_code AND m2.d <= 0.2)),
       NULL
  FROM #m WHERE d <= 0.2;
/* 5~20% 차이 예 */
SELECT TOP 12 u.kapt_name, u.kh, g.complex_nm, m.hhld_cnt_sum, 차 = CAST(m.d * 100 AS INT), u.kapt_usedate, g.oldest_use_apr, g.latest_use_apr
  FROM #m m JOIN #u u ON u.kapt_code = m.kapt_code JOIN gold.complex g ON g.complex_id = m.complex_id WHERE m.d > 0.05 AND m.d <= 0.2 ORDER BY NEWID();
/* 둘째 길(도로명)을 전국으로 풀면 */
IF OBJECT_ID('tempdb..#k') IS NOT NULL DROP TABLE #k;
SELECT u.kapt_code, u.kh, e.rn_mgt_sn, e.buld_mnnm, e.buld_slno INTO #k FROM #u u
  JOIN gold.v_juso_exact e ON e.keyword = CAST(LTRIM(RTRIM(LEFT(u.doro_juso, PATINDEX('%[0-9] %', u.doro_juso + ' ')))) AS NVARCHAR(300));
SELECT 도로명주소로_찾은_Kapt = (SELECT COUNT(DISTINCT kapt_code) FROM #k), 안된Kapt = (SELECT COUNT(*) FROM #u);
