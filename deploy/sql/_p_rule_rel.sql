/* ③ 같은 단지 · 같은 해 · 비슷한 면적(5㎡ 칸) 중앙값 대비 — 아파트 매매(해제 뺌), 같은 칸 거래 5건 이상만 */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
IF OBJECT_ID('tempdb..#t') IS NOT NULL DROP TABLE #t;
SELECT trade_sk, match_complex_id, deal_year, 칸 = CAST(FLOOR(exclu_use_ar / 5) AS INT), deal_amount, dealing_gbn, floor_no, bld_nm, deal_ymd, exclu_use_ar
INTO #t FROM silver.rtms_trade
WHERE trade_kind = 'APT_TRADE_DEV' AND ISNULL(cdeal_type, '') = '' AND match_complex_id IS NOT NULL AND deal_amount > 0 AND exclu_use_ar > 0;
IF OBJECT_ID('tempdb..#m') IS NOT NULL DROP TABLE #m;
SELECT DISTINCT match_complex_id, deal_year, 칸,
       중앙 = PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY deal_amount) OVER (PARTITION BY match_complex_id, deal_year, 칸),
       n = COUNT(*) OVER (PARTITION BY match_complex_id, deal_year, 칸)
INTO #m FROM #t;
IF OBJECT_ID('tempdb..#r') IS NOT NULL DROP TABLE #r;
SELECT t.*, m.중앙, m.n, 비 = t.deal_amount / m.중앙 INTO #r FROM #t t JOIN #m m ON m.match_complex_id = t.match_complex_id AND m.deal_year = t.deal_year AND m.칸 = t.칸 WHERE m.n >= 5;
SELECT 대상 = COUNT(*), 칸5건미만_빠짐 = (SELECT COUNT(*) FROM #t) - COUNT(*),
       반값미만 = SUM(CASE WHEN 비 < 0.5 THEN 1 ELSE 0 END), 셋에하나미만 = SUM(CASE WHEN 비 < 1.0/3 THEN 1 ELSE 0 END),
       두배초과 = SUM(CASE WHEN 비 > 2 THEN 1 ELSE 0 END), 세배초과 = SUM(CASE WHEN 비 > 3 THEN 1 ELSE 0 END),
       반값미만중_직거래 = SUM(CASE WHEN 비 < 0.5 AND dealing_gbn = N'직거래' THEN 1 ELSE 0 END)
FROM #r;
SELECT TOP 8 bld_nm, deal_ymd, exclu_use_ar, floor_no, deal_amount, 중앙 = CAST(중앙 AS BIGINT), 비 = CAST(비 AS DECIMAL(6,3)), dealing_gbn, n FROM #r WHERE 비 < 0.5 ORDER BY 비;
SELECT TOP 5 bld_nm, deal_ymd, exclu_use_ar, floor_no, deal_amount, 중앙 = CAST(중앙 AS BIGINT), 비 = CAST(비 AS DECIMAL(6,3)), dealing_gbn, n FROM #r WHERE 비 > 2 ORDER BY 비 DESC;
