/* 기존 실거래의 범위 (2026-10-19) - 안양을 같은 조건으로 받으려고 */
SET NOCOUNT ON;
SELECT sgg_cd,
       건수 = COUNT(*),
       최초 = MIN(deal_ymd), 최종 = MAX(deal_ymd),
       종목수 = COUNT(DISTINCT trade_kind)
  FROM silver.rtms_trade
 GROUP BY sgg_cd ORDER BY sgg_cd;

SELECT trade_kind, 건수 = COUNT(*)
  FROM silver.rtms_trade GROUP BY trade_kind ORDER BY COUNT(*) DESC;
