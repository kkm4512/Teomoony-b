SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT j = (SELECT 단지 = COUNT(DISTINCT kapt_code), 처음 = MIN(ym), 끝 = MAX(ym),
                   서울이음 = (SELECT COUNT(DISTINCT x.kapt_code) FROM gold.complex_kapt x),
                   서울이음_관리비 = (SELECT COUNT(DISTINCT x.kapt_code) FROM gold.complex_kapt x WHERE EXISTS (SELECT 1 FROM silver.kapt_cost c WHERE c.kapt_code = x.kapt_code)),
                   구 = (SELECT LEFT(k.bjd_code, 5) sgg, n = COUNT(DISTINCT c.kapt_code) FROM silver.kapt_cost c JOIN silver.kapt_complex k ON k.kapt_code = c.kapt_code AND k.is_current = 1 GROUP BY LEFT(k.bjd_code, 5) FOR JSON PATH)
              FROM silver.kapt_cost FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
