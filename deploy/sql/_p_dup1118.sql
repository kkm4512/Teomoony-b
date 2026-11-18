SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 종류 = trade_kind, 더함 = COUNT_BIG(*), 해제 = SUM(CAST(is_canceled AS INT)), 단지붙음 = SUM(CASE WHEN match_complex_id IS NOT NULL THEN 1 ELSE 0 END)
FROM silver.rtms_trade WHERE loaded_at >= '2026-11-18 13:44:00' GROUP BY trade_kind ORDER BY 2 DESC;
SELECT 전체 = COUNT_BIG(*) FROM silver.rtms_trade;
