/* 419b (2026-11-18 21:50): 419 에서 지운 9,841줄 중 **해제(cdeal_type='O')된 옛 줄 7,437줄을 되돌린다.**
   까닭: 이들은 '같은 거래가 두 번 들어간 것' 이 아니라 원천에 따로 있는 **해제된 원래 신고**로 보인다
   (해제일 = 새 줄의 등기일인 예가 많고, 새 줄보다 trade_sk 가 뒤 = 같은 받기에서 둘 다 내려옴). 원본을 지우지 않는다. */
SET XACT_ABORT ON;
DECLARE @c NVARCHAR(MAX) = (SELECT STRING_AGG(QUOTENAME(name), ',') WITHIN GROUP (ORDER BY column_id)
                            FROM sys.columns WHERE object_id = OBJECT_ID('silver.rtms_trade') AND is_computed = 0);
DECLARE @s NVARCHAR(MAX) = N'SET IDENTITY_INSERT silver.rtms_trade ON;
INSERT silver.rtms_trade (' + @c + N') SELECT ' + @c + N' FROM ops.rtms_dongdup_bak1118 b
WHERE b.cdeal_type = ''O'' AND NOT EXISTS (SELECT 1 FROM silver.rtms_trade t WHERE t.trade_sk = b.trade_sk);
SELECT 되돌림 = @@ROWCOUNT;
SET IDENTITY_INSERT silver.rtms_trade OFF;';
BEGIN TRAN; EXEC sp_executesql @s; COMMIT;
SELECT 백업중_해제 = SUM(CASE WHEN b.cdeal_type = 'O' THEN 1 ELSE 0 END), 백업중_안해제 = SUM(CASE WHEN ISNULL(b.cdeal_type,'') <> 'O' THEN 1 ELSE 0 END),
       되돌아옴 = COUNT(t.trade_sk)
FROM ops.rtms_dongdup_bak1118 b LEFT JOIN silver.rtms_trade t ON t.trade_sk = b.trade_sk;
