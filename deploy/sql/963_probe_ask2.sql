SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @t DATETIME2 = SYSDATETIME();
IF OBJECT_ID('tempdb..#a') IS NOT NULL DROP TABLE #a;
SELECT TOP (20) c.complex_id, t.max_amount INTO #a
  FROM gold.complex c
  OUTER APPLY (SELECT TOP 1 r.deal_amount AS max_amount FROM silver.rtms_trade r
                WHERE r.match_complex_id = c.complex_id AND r.is_rent = 0 AND r.is_canceled = 0 AND r.deal_amount IS NOT NULL
                ORDER BY r.deal_amount DESC) t
 WHERE c.is_active = 1 AND 1 = 1
   AND c.complex_id IN (SELECT TOP (90) m.complex_id FROM gold.complex_trade_max m JOIN gold.complex c ON c.complex_id = m.complex_id
                         WHERE m.종류 = 'ALL' AND c.is_active = 1 AND 1 = 1 ORDER BY m.max_amt DESC)
   AND t.max_amount IS NOT NULL
 ORDER BY t.max_amount DESC;
DECLARE @전국 INT = DATEDIFF(MILLISECOND, @t, SYSDATETIME());
SET @t = SYSDATETIME();
IF OBJECT_ID('tempdb..#b') IS NOT NULL DROP TABLE #b;
SELECT TOP (20) c.complex_id, t.max_amount INTO #b
  FROM gold.complex c
  OUTER APPLY (SELECT TOP 1 r.deal_amount AS max_amount FROM silver.rtms_trade r
                WHERE r.match_complex_id = c.complex_id AND r.is_rent = 0 AND r.is_canceled = 0 AND r.deal_amount IS NOT NULL
                ORDER BY r.deal_amount DESC) t
 WHERE c.is_active = 1 AND c.sigungu_cd = '11290' AND t.max_amount IS NOT NULL
 ORDER BY t.max_amount DESC;
DECLARE @성북옛 INT = DATEDIFF(MILLISECOND, @t, SYSDATETIME());
SET @t = SYSDATETIME();
IF OBJECT_ID('tempdb..#c') IS NOT NULL DROP TABLE #c;
SELECT TOP (20) c.complex_id, t.max_amount INTO #c
  FROM gold.complex c
  OUTER APPLY (SELECT TOP 1 r.deal_amount AS max_amount FROM silver.rtms_trade r
                WHERE r.match_complex_id = c.complex_id AND r.is_rent = 0 AND r.is_canceled = 0 AND r.deal_amount IS NOT NULL
                ORDER BY r.deal_amount DESC) t
 WHERE c.is_active = 1 AND c.sigungu_cd = '11290'
   AND c.complex_id IN (SELECT TOP (90) m.complex_id FROM gold.complex_trade_max m JOIN gold.complex c ON c.complex_id = m.complex_id
                         WHERE m.종류 = 'ALL' AND c.is_active = 1 AND c.sigungu_cd = '11290' ORDER BY m.max_amt DESC)
   AND t.max_amount IS NOT NULL
 ORDER BY t.max_amount DESC;
DECLARE @성북새 INT = DATEDIFF(MILLISECOND, @t, SYSDATETIME());
SELECT 전국새ms = @전국, 성북옛ms = @성북옛, 성북새ms = @성북새,
       같음 = CASE WHEN NOT EXISTS (SELECT complex_id, max_amount FROM #b EXCEPT SELECT complex_id, max_amount FROM #c)
                    AND NOT EXISTS (SELECT complex_id, max_amount FROM #c EXCEPT SELECT complex_id, max_amount FROM #b) THEN 1 ELSE 0 END,
       전국1등 = (SELECT TOP 1 CONCAT(a.complex_id, ' ', c.complex_nm, ' ', a.max_amount) FROM #a a JOIN gold.complex c ON c.complex_id = a.complex_id ORDER BY a.max_amount DESC);
