SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT (SELECT p.kapt_이름, p.kapt_세대, p.complex_id, p.남을코드, c.complex_nm, c.rep_plat_plc, c.hhld_cnt_sum, c.dong_cnt, c.oldest_use_apr, k.kapt_addr, k.dong_cnt AS kapt동,
               거래 = (SELECT COUNT(*) FROM silver.rtms_trade t WHERE t.match_complex_id = c.complex_id)
          FROM ops.complex_merge_plan_kapt p JOIN gold.complex c ON c.complex_id = p.complex_id JOIN silver.kapt_complex k ON k.kapt_code = p.kapt_code AND k.is_current = 1
         ORDER BY p.kapt_세대 DESC, p.complex_id FOR JSON PATH) AS j;
