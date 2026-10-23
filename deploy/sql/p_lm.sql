SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
IF OBJECT_ID('tempdb..#t') IS NOT NULL DROP TABLE #t;
SELECT t.trade_sk, t.trade_kind, t.bld_nm, t.deal_ymd, t.match_pnu, t.exclu_use_ar, t.deal_amount
  INTO #t FROM silver.rtms_trade t
 WHERE t.match_complex_id IS NULL AND t.match_pnu LIKE '11%' AND t.trade_kind NOT LIKE 'SILV%'
   AND NOT EXISTS (SELECT 1 FROM silver.cadastral_parcel p WHERE p.pnu = t.match_pnu AND p.is_current = 1);
IF OBJECT_ID('tempdb..#m') IS NOT NULL DROP TABLE #m;
SELECT t.*, 사유 = h.이동사유, 이동일 = h.이동일,
       대상 = LEFT(h.이동사유, CASE WHEN CHARINDEX(N'번과 합병되어 말소', h.이동사유) > 0 THEN CHARINDEX(N'번과 합병되어 말소', h.이동사유) - 1 ELSE 0 END)
  INTO #m FROM #t t
 CROSS APPLY (SELECT TOP 1 x.이동사유, x.이동일 FROM silver.land_move_hist x WHERE x.pnu = t.match_pnu ORDER BY x.이동일 DESC, x.이력순번 DESC) h
 WHERE h.이동사유 LIKE N'%번과 합병되어 말소';
DELETE FROM #m WHERE 대상 LIKE '%[^0-9-]%' OR LEN(대상) NOT BETWEEN 1 AND 9 OR 대상 LIKE '%-%-%';
ALTER TABLE #m ADD 새 CHAR(19);
UPDATE #m SET 새 = LEFT(match_pnu, 11) + RIGHT('0000' + CASE WHEN CHARINDEX('-', 대상) > 0 THEN LEFT(대상, CHARINDEX('-', 대상) - 1) ELSE 대상 END, 4)
                 + RIGHT('0000' + CASE WHEN CHARINDEX('-', 대상) > 0 THEN SUBSTRING(대상, CHARINDEX('-', 대상) + 1, 10) ELSE '0' END, 4);
SELECT r = (SELECT m.trade_kind 종류, m.bld_nm 실거래이름, m.deal_ymd 계약, m.exclu_use_ar 전용, m.deal_amount 금액, 옛지번 = m.match_pnu, 합병일 = m.이동일, 새지번 = m.새,
       단지 = (SELECT STRING_AGG(CONCAT(c.complex_nm, '(', c.oldest_use_apr, '·', c.hhld_cnt_sum, ')'), ' / ') FROM gold.complex_pnu cp JOIN gold.complex c ON c.complex_id = cp.complex_id AND c.is_active = 1 AND c.merged_into IS NULL WHERE cp.pnu = m.새)
  FROM #m m
 WHERE EXISTS (SELECT 1 FROM gold.complex_pnu cp JOIN gold.complex c ON c.complex_id = cp.complex_id AND c.is_active = 1 AND c.merged_into IS NULL AND c.hhld_cnt_sum > 0 WHERE cp.pnu = m.새)
 ORDER BY m.trade_kind, m.bld_nm, m.deal_ymd FOR JSON PATH);
