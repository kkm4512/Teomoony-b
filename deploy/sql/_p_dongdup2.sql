SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 옛 = ISNULL(b.cdeal_type,'(null)'), 새 = ISNULL(n.cdeal_type,'(null)'), 줄 = COUNT(*), 옛등기있음 = SUM(CASE WHEN ISNULL(b.rgst_date,'')<>'' THEN 1 ELSE 0 END),
       새등기있음 = SUM(CASE WHEN ISNULL(n.rgst_date,'')<>'' THEN 1 ELSE 0 END), 새해제일있음 = SUM(CASE WHEN ISNULL(n.cdeal_day,'')<>'' THEN 1 ELSE 0 END)
FROM ops.rtms_dongdup_bak1118 b LEFT JOIN silver.rtms_trade n ON n.trade_sk = b.n_sk
GROUP BY ISNULL(b.cdeal_type,'(null)'), ISNULL(n.cdeal_type,'(null)');
SELECT TOP 5 b.trade_sk, b.bld_nm, b.deal_ymd, b.deal_amount, b.cdeal_type, b.cdeal_day, b.rgst_date, n.trade_sk, n.bld_dong, n.cdeal_type, n.cdeal_day, n.rgst_date
FROM ops.rtms_dongdup_bak1118 b JOIN silver.rtms_trade n ON n.trade_sk = b.n_sk WHERE ISNULL(b.cdeal_type,'') <> ISNULL(n.cdeal_type,'');
