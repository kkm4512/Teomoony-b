EXEC meta.usp_refresh_coverage;
GO
SELECT j = (SELECT 자료, 시군구 = COUNT(*), 서울 = SUM(CASE WHEN sgg_cd LIKE '11%' THEN 1 ELSE 0 END), 모름 = SUM(CASE WHEN sgg_cd = '00000' THEN 행수 ELSE 0 END),
  행 = SUM(행수) FROM meta.coverage GROUP BY 자료 ORDER BY 자료 FOR JSON PATH);
