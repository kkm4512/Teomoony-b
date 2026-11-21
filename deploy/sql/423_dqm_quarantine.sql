/* 423 (2026-11-21 · DQM ③ 격리 적용 · 사장님 "알람은 제외하고 일단 진행해봐")
   규칙(etl/dqm_rules.yaml)에서 처리 = 격리 · 버림 인 규칙에 걸린 줄을 **제공에서 뺀다** — 지우지 않고 ops.dqm_quarantine 로 옮긴다.
   420(원천에서 사라진 줄 격리)과 같은 방식: 적재 표(silver.rtms_trade)에서 빼면 화면 질의 44곳 · 거래 요약(gold) · 서비스DB 발행이
   따로 고치지 않아도 모두 그 줄을 안 본다. 줄은 칸 그대로 ops.dqm_quarantine 에 남는다(사람이 보고 풀 수 있게).
   ★ 옮기는 일은 etl/dqm_rules.py apply 가 한다(규칙 run 바로 뒤 · 한 번에 2,000줄 넘으면 멈춤).
   ★ load_rtms 는 격리 중인 nat_key 를 다시 넣지 않는다(원천이 그 줄을 고치면 키가 바뀌어 새 줄로 들어오고, 규칙이 다시 본다).
   ★ 풀기(사람이 보고 진짜 거래라고 판단했을 때): EXEC ops.usp_dqm_release @trade_sk = N, @why = N'...';
     → 줄을 원래 trade_sk 그대로 silver 에 되돌리고, 격리 표에는 풀림 · 사유를 남긴다(다음 규칙 run 이 다시 격리하지 않게 예외로도 쓴다). */
SET QUOTED_IDENTIFIER ON; SET ANSI_NULLS ON;
IF OBJECT_ID('ops.dqm_quarantine') IS NULL
BEGIN
    DECLARE @c NVARCHAR(MAX) = (SELECT STRING_AGG(QUOTENAME(name), ',') WITHIN GROUP (ORDER BY column_id)
                                FROM sys.columns WHERE object_id = OBJECT_ID('silver.rtms_trade') AND is_computed = 0);
    DECLARE @mk NVARCHAR(MAX) = N'SELECT TOP 0 ' + REPLACE(@c, N'[trade_sk]', N'[trade_sk] = [trade_sk] + 0')
        + N', run_id = CAST(0 AS INT), rule_ids = CAST(NULL AS VARCHAR(200)), 격리시각 = SYSDATETIME(),'
        + N' 풀림 = CAST(NULL AS DATETIME2), 풀림사유 = CAST(NULL AS NVARCHAR(200)) INTO ops.dqm_quarantine FROM silver.rtms_trade';
    EXEC sp_executesql @mk;
    CREATE UNIQUE INDEX ux_dqm_quarantine_sk ON ops.dqm_quarantine (trade_sk);
    CREATE INDEX ix_dqm_quarantine_nat ON ops.dqm_quarantine (nat_key) INCLUDE (풀림);
END
GO
CREATE OR ALTER PROCEDURE ops.usp_dqm_release @trade_sk BIGINT, @why NVARCHAR(200)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF NOT EXISTS (SELECT 1 FROM ops.dqm_quarantine WHERE trade_sk = @trade_sk AND 풀림 IS NULL) BEGIN SELECT 결과 = N'격리 중인 줄이 아니다'; RETURN; END;
    DECLARE @c NVARCHAR(MAX) = (SELECT STRING_AGG(QUOTENAME(name), ',') WITHIN GROUP (ORDER BY column_id)
                                FROM sys.columns WHERE object_id = OBJECT_ID('silver.rtms_trade') AND is_computed = 0);
    DECLARE @s NVARCHAR(MAX) = N'SET IDENTITY_INSERT silver.rtms_trade ON; INSERT silver.rtms_trade (' + @c + N') SELECT ' + @c
        + N' FROM ops.dqm_quarantine WHERE trade_sk = @sk; SET IDENTITY_INSERT silver.rtms_trade OFF;';
    BEGIN TRAN;
    EXEC sp_executesql @s, N'@sk BIGINT', @sk = @trade_sk;
    UPDATE ops.dqm_quarantine SET 풀림 = SYSDATETIME(), 풀림사유 = @why WHERE trade_sk = @trade_sk;
    COMMIT;
    SELECT 결과 = N'풀었다', trade_sk = @trade_sk;
END
GO
