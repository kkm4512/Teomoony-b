SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT j = (SELECT deal_year, n = COUNT(*), 분양권 = SUM(CASE WHEN ownership_gbn = N'분' THEN 1 ELSE 0 END), 입주권 = SUM(CASE WHEN ownership_gbn = N'입' THEN 1 ELSE 0 END),
                   필지찾음 = SUM(CASE WHEN match_pnu IS NULL THEN 0 ELSE 1 END)
              FROM silver.rtms_trade WHERE trade_kind = 'SILV_TRADE' AND sgg_cd LIKE '11%' GROUP BY deal_year ORDER BY deal_year FOR JSON PATH);
