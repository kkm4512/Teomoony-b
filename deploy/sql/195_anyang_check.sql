/* 안양 적재 결과 확인 (2026-10-19)
   "안양 제일 비싼" 이 SCOPE 를 벗어났는지 세어서 본다. 추측하지 않는다. */
SET NOCOUNT ON;

SELECT 구분 = '단지(gold.complex)',
       만안 = SUM(CASE WHEN sigungu_cd = '41171' THEN 1 ELSE 0 END),
       동안 = SUM(CASE WHEN sigungu_cd = '41173' THEN 1 ELSE 0 END),
       양재 = SUM(CASE WHEN LEFT(rep_pnu,10) = '1165010200' THEN 1 ELSE 0 END)
  FROM gold.complex WHERE is_active = 1;

SELECT 구분 = '실거래(silver.rtms_trade)',
       만안 = SUM(CASE WHEN sgg_cd = '41171' THEN 1 ELSE 0 END),
       동안 = SUM(CASE WHEN sgg_cd = '41173' THEN 1 ELSE 0 END)
  FROM silver.rtms_trade;

/* 안양에서 제일 비싼 5곳 - 화면에서 물어볼 질문을 미리 돌려본다 */
SELECT TOP 5
       c.complex_nm, c.rep_plat_plc,
       최고가억 = CAST(t.max_amount / 100000000.0 AS DECIMAL(6,1)),
       t.trade_kind, 거래일 = t.max_ymd
  FROM gold.complex c
  OUTER APPLY (SELECT TOP 1 r.deal_amount AS max_amount, r.deal_ymd AS max_ymd, r.trade_kind
                 FROM silver.rtms_trade r
                WHERE r.match_complex_id = c.complex_id AND r.is_rent = 0
                  AND r.is_canceled = 0 AND r.deal_amount IS NOT NULL
                ORDER BY r.deal_amount DESC) t
 WHERE c.is_active = 1 AND c.sigungu_cd IN ('41171','41173')
   AND t.max_amount IS NOT NULL
 ORDER BY t.max_amount DESC;
