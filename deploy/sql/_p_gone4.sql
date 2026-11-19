SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 전체 = COUNT_BIG(*) FROM silver.rtms_trade;
SELECT 종류 = trade_kind, 더함 = COUNT_BIG(*) FROM silver.rtms_trade WHERE loaded_at >= '2026-11-19 04:01:00' AND loaded_at < '2026-11-19 05:44:00' GROUP BY trade_kind ORDER BY 2 DESC;
