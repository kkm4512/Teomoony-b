/* 원천에서 사라진 줄 후보 생김새(읽기만) — 가장 최근 run */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @run INT = (SELECT MAX(run_id) FROM ops.rtms_gone_run WHERE 끝 IS NOT NULL);
IF OBJECT_ID('tempdb..#c') IS NOT NULL DROP TABLE #c;
SELECT t.trade_sk, t.is_canceled, t.match_complex_id,
       가격만 = CASE WHEN EXISTS (SELECT 1 FROM silver.rtms_trade o WHERE o.trade_sk <> t.trade_sk AND o.trade_kind = t.trade_kind AND o.sgg_cd = t.sgg_cd
            AND ISNULL(o.umd_nm,N'') = ISNULL(t.umd_nm,N'') AND ISNULL(o.deal_ymd,'') = ISNULL(t.deal_ymd,'') AND ISNULL(o.jibun,N'') = ISNULL(t.jibun,N'')
            AND ISNULL(o.bld_nm,N'') = ISNULL(t.bld_nm,N'') AND ISNULL(o.exclu_use_ar,-1) = ISNULL(t.exclu_use_ar,-1) AND ISNULL(o.floor_no,-9999) = ISNULL(t.floor_no,-9999)
            AND (ISNULL(o.deal_amount,-1) <> ISNULL(t.deal_amount,-1) OR ISNULL(o.deposit,-1) <> ISNULL(t.deposit,-1) OR ISNULL(o.monthly_rent,-1) <> ISNULL(t.monthly_rent,-1))
            AND NOT EXISTS (SELECT 1 FROM ops.rtms_gone_cand c2 WHERE c2.run_id = @run AND c2.trade_sk = o.trade_sk)) THEN 1 ELSE 0 END
INTO #c FROM ops.rtms_gone_cand c JOIN silver.rtms_trade t ON t.trade_sk = c.trade_sk WHERE c.run_id = @run;
SELECT run = @run, 후보 = COUNT(*), 해제 = SUM(CAST(is_canceled AS INT)), 단지붙음 = SUM(CASE WHEN match_complex_id IS NOT NULL THEN 1 ELSE 0 END), 가격만다른줄있음 = SUM(가격만) FROM #c;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @run INT = (SELECT MAX(run_id) FROM ops.rtms_gone_run WHERE 끝 IS NOT NULL);
SELECT 종류 = c.trade_kind, 후보 = COUNT(*), 최초 = MIN(c.ym), 최근 = MAX(c.ym), 묶음 = COUNT(DISTINCT c.sgg_cd + c.ym) FROM ops.rtms_gone_cand c WHERE c.run_id = @run GROUP BY c.trade_kind ORDER BY 2 DESC;
SELECT 연 = LEFT(c.ym,4), 후보 = COUNT(*) FROM ops.rtms_gone_cand c WHERE c.run_id = @run GROUP BY LEFT(c.ym,4) ORDER BY 1;
SELECT TOP 8 b.trade_kind, b.sgg_cd, b.ym, b.원천줄, b.적재줄, b.적재에만, b.원천에만 FROM ops.rtms_gone_bundle b WHERE b.run_id = @run ORDER BY b.적재에만 DESC;
