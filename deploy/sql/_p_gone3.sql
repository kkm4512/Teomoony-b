SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 연 = LEFT(ym,4), 원천에만 = SUM(원천에만), 적재에만 = SUM(적재에만) FROM ops.rtms_gone_bundle WHERE run_id = 3 GROUP BY LEFT(ym,4) HAVING SUM(원천에만) + SUM(적재에만) > 0 ORDER BY 1;
SELECT TOP 8 trade_kind, sgg_cd, ym, 원천줄, 적재줄, 적재에만, 원천에만 FROM ops.rtms_gone_bundle WHERE run_id = 3 ORDER BY 원천에만 DESC;
