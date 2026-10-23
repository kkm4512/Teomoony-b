/* 314 를 나눈 것(2026-10-23) — _apply 긴 풀 20분 한도 안에 하나씩. 일꾼(z-askattr-par)은 314 하나로 sqlcmd(한도 없음) 그대로 */
SET NOCOUNT ON;
EXEC gold.usp_refresh_ask_attr @what = 'station';
SELECT 표, 굳힌때, 행수 FROM gold.ask_attr_meta ORDER BY 표;
