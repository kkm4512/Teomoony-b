SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @run INT = (SELECT MAX(run_id) FROM ops.dqm_rule_run WHERE 끝 IS NOT NULL);
SELECT run_id, 시작 = DATEADD(HOUR, 9, 시작), 끝 = DATEADD(HOUR, 9, 끝), 규칙버전, 규칙수, 대상줄, 메모 FROM ops.dqm_rule_run WHERE run_id = @run;
SELECT rule_id, 처리, 대상줄, 걸린줄, 예시짧게 = LEFT(예시, 160) FROM ops.dqm_rule_stat WHERE run_id = @run AND rule_id IN ('R06','R07a') ORDER BY rule_id;
SELECT trade_kind, 줄, A, B, C, 격리 FROM ops.dqm_grade_stat WHERE run_id = @run ORDER BY 줄 DESC;
DECLARE @sk BIGINT = (SELECT TOP 1 trade_sk FROM ops.dqm_rule_hit WHERE run_id = @run AND rule_id = 'R07a');
SELECT 예_sk = @sk, h.rule_id, s.이름, s.처리 FROM ops.dqm_rule_hit h JOIN ops.dqm_rule_stat s ON s.run_id = h.run_id AND s.rule_id = h.rule_id WHERE h.run_id = @run AND h.trade_sk = @sk;
