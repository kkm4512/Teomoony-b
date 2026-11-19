/* 420 (2026-11-19 · DQM 'D' · 사장님 ㄱㄱ): 원천(국토부 API)에서 사라진 실거래 줄을 **격리**한다 — 지우지 않고 ops.rtms_gone_bak 로 옮기고 적재 표에서 뺀다.
   후보 = 가장 최근에 끝난 rtms_gone.py run 의 ops.rtms_gone_cand(받기가 OK 인 묶음만 · load_rtms 와 같은 순번 키로 대조).
   생김새(11-19 실측): 지번이 바뀐 거래(예 동대문 257-42 → 432) · 가격 정정 전 줄 · 철회된 신고.
   ★ rtms_gone 을 돌린 바로 뒤에 건다(그 사이 적재가 돌면 후보가 바뀔 수 있다 — run 이 끝난 지 90분 넘으면 멈춘다).
   ★ 되돌리기: SET IDENTITY_INSERT silver.rtms_trade ON; INSERT silver.rtms_trade (계산칸 뺀 칸들) SELECT 같은 칸 FROM ops.rtms_gone_bak WHERE run_id = N; (419b 처럼)
   원천에 다시 나타난 줄은 load_rtms 가 다음 받기 때 새 줄로 넣는다. */
SET XACT_ABORT ON;
DECLARE @run INT, @끝 DATETIME2;
SELECT TOP 1 @run = run_id, @끝 = 끝 FROM ops.rtms_gone_run WHERE 끝 IS NOT NULL ORDER BY run_id DESC;
IF DATEDIFF(MINUTE, @끝, SYSDATETIME()) > 90 BEGIN SELECT 멈춤 = N'run ' + CAST(@run AS NVARCHAR) + N' 이 오래됐다 — rtms_gone 을 다시 돌린다'; RETURN; END;
SELECT run = @run, 후보 = COUNT(*), 키그대로 = SUM(CASE WHEN t.nat_key = c.nat_key THEN 1 ELSE 0 END) FROM ops.rtms_gone_cand c LEFT JOIN silver.rtms_trade t ON t.trade_sk = c.trade_sk WHERE c.run_id = @run;
-- ★ 키가 바뀐 줄(그 사이 적재가 고친 줄)은 격리하지 않는다 — 아래 JOIN 에 nat_key 를 함께 건다.
DECLARE @c NVARCHAR(MAX) = (SELECT STRING_AGG(QUOTENAME(name), ',') WITHIN GROUP (ORDER BY column_id)
                            FROM sys.columns WHERE object_id = OBJECT_ID('silver.rtms_trade') AND is_computed = 0);
DECLARE @ct NVARCHAR(MAX) = (SELECT STRING_AGG(N't.' + QUOTENAME(name), ',') WITHIN GROUP (ORDER BY column_id)
                             FROM sys.columns WHERE object_id = OBJECT_ID('silver.rtms_trade') AND is_computed = 0);
IF OBJECT_ID('ops.rtms_gone_bak') IS NULL   -- trade_sk + 0: IDENTITY 를 떼어 낸다(그대로면 INSERT 가 막힌다)
BEGIN
    DECLARE @mk NVARCHAR(MAX) = N'SELECT TOP 0 ' + REPLACE(@c, N'[trade_sk]', N'[trade_sk] = [trade_sk] + 0') + N', run_id = CAST(0 AS INT), 격리시각 = SYSDATETIME() INTO ops.rtms_gone_bak FROM silver.rtms_trade';
    EXEC sp_executesql @mk;
END
BEGIN TRAN;
DECLARE @ins NVARCHAR(MAX) = N'INSERT ops.rtms_gone_bak (' + @c + N', run_id, 격리시각) SELECT ' + @ct + N', c.run_id, SYSDATETIME() FROM silver.rtms_trade t JOIN ops.rtms_gone_cand c ON c.trade_sk = t.trade_sk AND c.nat_key = t.nat_key WHERE c.run_id = @run';
EXEC sp_executesql @ins, N'@run INT', @run = @run;
DELETE t FROM silver.rtms_trade t JOIN ops.rtms_gone_cand c ON c.trade_sk = t.trade_sk
WHERE c.run_id = @run AND EXISTS (SELECT 1 FROM ops.rtms_gone_bak b WHERE b.trade_sk = t.trade_sk AND b.run_id = @run);
SELECT 격리 = @@ROWCOUNT;
COMMIT;
SELECT 종류 = trade_kind, 격리 = COUNT(*), 단지수 = COUNT(DISTINCT match_complex_id) FROM ops.rtms_gone_bak WHERE run_id = @run GROUP BY trade_kind ORDER BY 2 DESC;
