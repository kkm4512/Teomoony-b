SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT (SELECT t.match_complex_id, t.apt_seq, t.bld_nm, t.jibun, n = COUNT(*), 처음 = MIN(t.deal_ymd), 끝 = MAX(t.deal_ymd)
          FROM silver.rtms_trade t WHERE t.match_complex_id IN (298508, 298509, 298688, 70072, 298577, 287515, 539824)
           AND t.trade_kind IN ('APT_TRADE_DEV', 'APT_RENT')
         GROUP BY t.match_complex_id, t.apt_seq, t.bld_nm, t.jibun ORDER BY t.match_complex_id, COUNT(*) DESC FOR JSON PATH) AS j;
