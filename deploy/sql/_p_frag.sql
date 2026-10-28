SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT c.complex_id, c.complex_nm, c.has_recap, c.dong_cnt, c.hhld_cnt_sum, c.grouping_rule, c.root_bldrgst_pk, c.oldest_use_apr
  FROM gold.complex c JOIN gold.complex_pnu p ON p.complex_id = c.complex_id
 WHERE p.pnu = '1215013300107660000' AND c.merged_into IS NULL ORDER BY c.complex_id;
SELECT 총괄표제부 = (SELECT COUNT(*) FROM silver.bld_recap_title WHERE pnu = '1215013300107660000' AND is_current = 1),
       표제부 = (SELECT COUNT(*) FROM silver.bld_title WHERE pnu = '1215013300107660000' AND is_current = 1);
SELECT TOP 12 dong_nm, main_purps_nm, hhld_cnt, use_apr_day, bld_nm FROM silver.bld_title WHERE pnu = '1215013300107660000' AND is_current = 1 ORDER BY dong_nm;
SELECT apt_seq, 거래 = COUNT(*), 이름 = MAX(bld_nm), 건축년도 = MIN(build_year), 붙은단지수 = COUNT(DISTINCT match_complex_id)
  FROM silver.rtms_trade WHERE match_pnu = '1215013300107660000' GROUP BY apt_seq;
SELECT 쪼개진필지 = COUNT(*), 총괄없음 = SUM(CASE WHEN r = 0 THEN 1 ELSE 0 END) FROM (
  SELECT a.pnu, r = (SELECT COUNT(*) FROM silver.bld_recap_title rt WHERE rt.pnu = a.pnu AND rt.is_current = 1)
    FROM (SELECT cp.pnu FROM gold.complex_pnu cp JOIN gold.complex c ON c.complex_id = cp.complex_id AND c.merged_into IS NULL AND c.hhld_cnt_sum > 0
           GROUP BY cp.pnu HAVING COUNT(DISTINCT cp.complex_id) > 1) a) z;
