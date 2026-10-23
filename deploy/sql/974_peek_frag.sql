SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT (SELECT TOP 40 c.complex_id, c.complex_nm, c.rep_plat_plc, c.hhld_cnt_sum, c.dong_cnt, c.pnu_cnt, c.oldest_use_apr, c.grouping_rule, c.has_recap,
               kapt = (SELECT TOP 1 x.kapt_name FROM gold.complex_kapt x WHERE x.complex_id = c.complex_id)
          FROM gold.complex c WHERE c.is_active = 1 AND c.sigungu_cd = '11350' AND c.oldest_use_apr IN ('19880727', '19880923', '19871121', '19880513')
           AND c.hhld_cnt_sum > 0 ORDER BY c.oldest_use_apr, c.rep_plat_plc FOR JSON PATH) AS a,
       (SELECT k.kapt_name, k.pnu, k.kapt_usedate, k.ho_cnt, k.dong_cnt, k.kapt_addr FROM silver.kapt_complex k WHERE k.is_current = 1 AND k.kapt_name LIKE N'상계주공[0-9]%' FOR JSON PATH) AS b,
       (SELECT 규칙 = grouping_rule, n = COUNT(*), 세대 = SUM(hhld_cnt_sum) FROM gold.complex WHERE is_active = 1 AND sigungu_cd LIKE '11%' AND hhld_cnt_sum > 0 GROUP BY grouping_rule FOR JSON PATH) AS c;
