SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 연결된Kapt = (SELECT COUNT(DISTINCT kapt_code) FROM gold.complex_kapt), 지금Kapt = (SELECT COUNT(DISTINCT kapt_code) FROM silver.kapt_complex WHERE is_current = 1);
IF OBJECT_ID('tempdb..#u') IS NOT NULL DROP TABLE #u;
SELECT k.kapt_code, k.kapt_name, k.pnu, k.bjd_code, k.kapt_usedate, kh = COALESCE(NULLIF(k.hhld_cnt, 0), k.ho_cnt), k.use_yn, k.code_apt_nm, k.kapt_addr
  INTO #u FROM silver.kapt_complex k WHERE k.is_current = 1 AND NOT EXISTS (SELECT 1 FROM gold.complex_kapt ck WHERE ck.kapt_code = k.kapt_code);
/* 그 지번의 세대 단지 */
IF OBJECT_ID('tempdb..#c') IS NOT NULL DROP TABLE #c;
SELECT u.kapt_code, c.complex_id, c.hhld_cnt_sum, c.oldest_use_apr, c.latest_use_apr, 이미Kapt = CASE WHEN EXISTS (SELECT 1 FROM gold.complex_kapt x WHERE x.complex_id = c.complex_id) THEN 1 ELSE 0 END
  INTO #c FROM #u u JOIN gold.complex_pnu cp ON cp.pnu = u.pnu JOIN gold.complex c ON c.complex_id = cp.complex_id AND c.merged_into IS NULL AND ISNULL(c.hhld_cnt_sum, 0) > 0;
ALTER TABLE #u ADD 원인 NVARCHAR(80) NULL;
UPDATE u SET 원인 = CASE
    WHEN u.pnu IS NULL THEN N'1 K-apt 지번 없음'
    WHEN NOT EXISTS (SELECT 1 FROM gold.complex_pnu cp WHERE cp.pnu = u.pnu) THEN N'2 그 지번에 우리 단지 없음'
    WHEN NOT EXISTS (SELECT 1 FROM #c c WHERE c.kapt_code = u.kapt_code) THEN N'3 그 지번에 세대 있는 단지 없음'
    WHEN NOT EXISTS (SELECT 1 FROM #c c WHERE c.kapt_code = u.kapt_code AND c.이미Kapt = 0) THEN N'4 그 지번 단지가 이미 다른 K-apt 와 이어짐'
    WHEN u.kapt_usedate IS NULL OR u.kapt_usedate = '' THEN N'5 K-apt 사용승인일 없음'
    WHEN NOT EXISTS (SELECT 1 FROM #c c WHERE c.kapt_code = u.kapt_code AND c.이미Kapt = 0 AND u.kapt_usedate BETWEEN c.oldest_use_apr AND ISNULL(c.latest_use_apr, c.oldest_use_apr)) THEN N'6 사용승인일 다름'
    WHEN NOT EXISTS (SELECT 1 FROM #c c WHERE c.kapt_code = u.kapt_code AND c.이미Kapt = 0 AND ABS(c.hhld_cnt_sum - u.kh) <= 0.2 * u.kh) THEN N'7 세대 20% 넘게 다름'
    ELSE N'8 조건은 맞는데 안 이어짐(같은 법정동 같은 날 단지 여럿 등)' END
  FROM #u u;
SELECT 원인, n = COUNT(*), 세대합 = SUM(kh) FROM #u GROUP BY 원인 ORDER BY 1;
SELECT 사용여부 = ISNULL(use_yn, '-'), n = COUNT(*) FROM #u GROUP BY use_yn;
SELECT 유형 = ISNULL(code_apt_nm, '-'), n = COUNT(*) FROM #u GROUP BY code_apt_nm ORDER BY 2 DESC;
SELECT TOP 6 원인, kapt_code, kapt_name, kapt_addr, kapt_usedate, kh,
       후보 = (SELECT STRING_AGG(CONCAT(c.complex_id, ':', g.complex_nm, '(', c.hhld_cnt_sum, '세대 ', c.oldest_use_apr, '~', c.latest_use_apr, CASE WHEN c.이미Kapt = 1 THEN ' 이미' ELSE '' END, ')'), ' / ') FROM #c c JOIN gold.complex g ON g.complex_id = c.complex_id WHERE c.kapt_code = u.kapt_code)
  FROM #u u WHERE 원인 LIKE N'4%' ORDER BY NEWID();
SELECT TOP 6 원인, kapt_code, kapt_name, kapt_addr, kapt_usedate, kh,
       후보 = (SELECT STRING_AGG(CONCAT(c.complex_id, ':', g.complex_nm, '(', c.hhld_cnt_sum, '세대 ', c.oldest_use_apr, '~', c.latest_use_apr, ')'), ' / ') FROM #c c JOIN gold.complex g ON g.complex_id = c.complex_id WHERE c.kapt_code = u.kapt_code)
  FROM #u u WHERE 원인 LIKE N'6%' ORDER BY NEWID();
SELECT TOP 6 원인, kapt_code, kapt_name, kapt_addr, pnu, kapt_usedate, kh FROM #u u WHERE 원인 LIKE N'2%' ORDER BY NEWID();
SELECT TOP 6 원인, kapt_code, kapt_name, kapt_addr, kapt_usedate, kh,
       후보 = (SELECT STRING_AGG(CONCAT(c.complex_id, ':', g.complex_nm, '(', c.hhld_cnt_sum, '세대 ', c.oldest_use_apr, ')'), ' / ') FROM #c c JOIN gold.complex g ON g.complex_id = c.complex_id WHERE c.kapt_code = u.kapt_code)
  FROM #u u WHERE 원인 LIKE N'7%' OR 원인 LIKE N'8%' ORDER BY NEWID();
