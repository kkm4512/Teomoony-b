SET NOCOUNT ON;
SELECT complex_id, complex_nm, rep_plat_plc, sigungu_cd, dong_cnt, hhld_cnt_sum, merged_into FROM gold.complex WHERE complex_id IN (722419, 722420, 722428);
SELECT 단지 = COUNT(*), 살아있음 = SUM(CASE WHEN merged_into IS NULL THEN 1 ELSE 0 END), 흡수 = SUM(CASE WHEN merged_into IS NOT NULL THEN 1 ELSE 0 END),
       동연결 = (SELECT COUNT(*) FROM gold.complex_bld cb JOIN gold.complex c2 ON c2.complex_id = cb.complex_id WHERE c2.sigungu_cd = '12150'),
       시대동 = (SELECT COUNT(*) FROM gold.complex_bld WHERE complex_id = 722419)
  FROM gold.complex WHERE sigungu_cd = '12150';
GO
EXEC gold.usp_build_complexes @sigungu_cd = '12150', @bjdong_cd = NULL;
GO
SELECT complex_id, complex_nm, dong_cnt, hhld_cnt_sum, merged_into FROM gold.complex WHERE complex_id IN (722419, 722420, 722428);
SELECT 단지 = COUNT(*), 살아있음 = SUM(CASE WHEN merged_into IS NULL THEN 1 ELSE 0 END), 흡수 = SUM(CASE WHEN merged_into IS NOT NULL THEN 1 ELSE 0 END),
       동연결 = (SELECT COUNT(*) FROM gold.complex_bld cb JOIN gold.complex c2 ON c2.complex_id = cb.complex_id WHERE c2.sigungu_cd = '12150'),
       시대동 = (SELECT COUNT(*) FROM gold.complex_bld WHERE complex_id = 722419),
       흡수조각에동 = (SELECT COUNT(*) FROM gold.complex_bld cb JOIN gold.complex c3 ON c3.complex_id = cb.complex_id WHERE c3.merged_into IS NOT NULL)
  FROM gold.complex WHERE sigungu_cd = '12150';
