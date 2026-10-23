SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT j = (SELECT TOP 4 school_id, school_nm, school_se, lnmadr, cddc_code, edc_sport, reference_date, is_current FROM silver.school WHERE school_nm IN (N'광운초등학교', N'대광초등학교') FOR JSON PATH);
GO
SELECT j = (SELECT 전체 = COUNT(*), 서울 = SUM(CASE WHEN lnmadr LIKE N'서울%' OR rdnmadr LIKE N'서울%' THEN 1 ELSE 0 END),
  앞글자 = (SELECT TOP 5 p = LEFT(school_id, 1), n = COUNT(*) FROM silver.school WHERE is_current = 1 GROUP BY LEFT(school_id, 1) ORDER BY 2 DESC FOR JSON PATH)
  FROM silver.school WHERE is_current = 1 FOR JSON PATH);
