/* 283 : 282 의 규칙으로 실거래 ↔ 단지를 다시 붙이고 요약을 다시 계산한다 (뒷줄 작업 ab-tradepick-bg) */
SET NOCOUNT ON;
SELECT 전_잠실어린이집 = (SELECT trade_cnt FROM gold.complex WHERE complex_id = 524689),
       전_파크리오     = (SELECT trade_cnt FROM gold.complex WHERE complex_id = 524691);
GO
EXEC gold.usp_match_complex_trade;
GO
EXEC gold.usp_refresh_complex_trade;
GO
EXEC gold.usp_refresh_complex_alias;   -- 285: 고쳐 붙인 거래로 실거래 이름을 다시 굳힌다
GO
SET NOCOUNT ON;
SELECT 후_잠실어린이집 = (SELECT trade_cnt FROM gold.complex WHERE complex_id = 524689),
       후_파크리오     = (SELECT trade_cnt FROM gold.complex WHERE complex_id = 524691);
GO
SET NOCOUNT ON;
/* 남은 것: 세대 0 단지에 붙은 주거 거래인데 같은 필지에 세대 있는 단지가 있다 → 0 이어야 한다 */
SELECT 남은_잘못붙음 = COUNT(*)
  FROM silver.rtms_trade t
  JOIN gold.complex c ON c.complex_id = t.match_complex_id AND ISNULL(c.hhld_cnt_sum, 0) = 0
 WHERE (t.trade_kind LIKE 'APT%' OR t.trade_kind LIKE 'RH%')
   AND EXISTS (SELECT 1 FROM gold.complex_pnu cp JOIN gold.complex c2 ON c2.complex_id = cp.complex_id
                WHERE cp.pnu = t.match_pnu AND c2.hhld_cnt_sum > 0);
GO
