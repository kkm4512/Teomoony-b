SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT j = (SELECT TOP 15 c.complex_id, c.complex_nm, c.oldest_use_apr, c.hhld_cnt_sum, 옛세대 = SUM(s.총괄세대), 옛 = COUNT(*)
  FROM gold.complex c JOIN gold.complex_pnu cp ON cp.complex_id = c.complex_id JOIN gold.closed_site s ON s.pnu = cp.pnu
 WHERE c.is_active = 1 AND c.hhld_cnt_sum > 300 AND c.oldest_use_apr >= '2015' AND s.총괄세대 > 50
 GROUP BY c.complex_id, c.complex_nm, c.oldest_use_apr, c.hhld_cnt_sum ORDER BY SUM(s.총괄세대) DESC FOR JSON PATH);
