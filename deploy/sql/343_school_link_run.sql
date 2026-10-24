SET NOCOUNT ON;
/* 학교알리미 ↔ 학교 위치 잇기 다시(335 규칙 그대로) — 새로 받은 시군구(안양 등)가 생기면 */
EXEC gold.usp_refresh_school_link;
GO
SELECT 이음 = COUNT(*), 시군구 = COUNT(DISTINCT LEFT(i.adrcd_cd,5)) FROM gold.school_link l JOIN silver.schoolinfo i ON i.schul_code = l.schul_code;
