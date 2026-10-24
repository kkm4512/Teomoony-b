SET NOCOUNT ON;
EXEC gold.usp_change_log_land_char;
GO
SELECT j=(SELECT 칼럼, 종류, n = COUNT(*), 필지 = COUNT(DISTINCT 키) FROM gold.change_log WHERE 자료 = N'토지특성' GROUP BY 칼럼, 종류 FOR JSON PATH);
GO
