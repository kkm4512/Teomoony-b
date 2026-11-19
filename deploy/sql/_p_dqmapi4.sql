SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @run INT = (SELECT MAX(run_id) FROM ops.dqm_rule_run WHERE 끝 IS NOT NULL);
SELECT TOP 6 t.trade_sk, t.trade_kind, t.bld_nm, t.umd_nm, t.deal_ymd, t.deal_amount, t.exclu_use_ar, t.floor_no, t.match_complex_id
  FROM silver.rtms_trade t WHERE t.trade_kind = 'APT_TRADE_DEV' AND t.deal_ymd >= CONVERT(CHAR(8), DATEADD(DAY, -60, SYSDATETIME()), 112)
   AND NOT EXISTS (SELECT 1 FROM ops.dqm_rule_hit h WHERE h.run_id = @run AND h.trade_sk = t.trade_sk) ORDER BY NEWID();
DECLARE @sk BIGINT = 4066201;
SELECT run = @run, 규칙수 = (SELECT COUNT(*) FROM ops.dqm_rule_stat WHERE run_id = @run);
SELECT h.rule_id, s.이름, s.처리 FROM ops.dqm_rule_hit h JOIN ops.dqm_rule_stat s ON s.run_id = h.run_id AND s.rule_id = h.rule_id WHERE h.run_id = @run AND h.trade_sk = @sk;
SELECT 있음 = COUNT(*) FROM silver.rtms_trade WHERE trade_sk = @sk;
