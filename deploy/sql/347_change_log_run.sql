SET NOCOUNT ON;
/* 347 변경 로그 다시 만들기 — 토지특성(전부). 적재(zz-landchar)가 끝나면 다시 돌린다 */
EXEC gold.usp_change_log_land_char;
GO
SELECT 칼럼, 종류, n = COUNT(*), 필지 = COUNT(DISTINCT 키) FROM gold.change_log WHERE 자료 = N'토지특성' GROUP BY 칼럼, 종류 ORDER BY 종류, n DESC;
