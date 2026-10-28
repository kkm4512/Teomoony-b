SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT OBJECT_NAME(object_id), STRING_AGG(name, ',') FROM sys.columns WHERE object_id IN (OBJECT_ID('silver.bld_atch_jibun'), OBJECT_ID('silver.bld_recap_title')) GROUP BY object_id;
SELECT TOP 3 * FROM silver.bld_atch_jibun;
SELECT 주택표제부 = COUNT(*), 허가번호있음 = SUM(CASE WHEN pmsno_year IS NOT NULL AND pmsno_kik_cd IS NOT NULL THEN 1 ELSE 0 END),
       허가일있음 = SUM(CASE WHEN LEN(pms_day) = 8 THEN 1 ELSE 0 END), 사용승인있음 = SUM(CASE WHEN LEN(use_apr_day) = 8 THEN 1 ELSE 0 END),
       도로명있음 = SUM(CASE WHEN na_road_cd IS NOT NULL THEN 1 ELSE 0 END)
  FROM silver.bld_title WHERE is_current = 1 AND main_purps_nm LIKE N'%공동주택%';
SELECT TOP 11 dong_nm, pmsno_year, pmsno_kik_cd, pmsno_gb_cd, pms_day, stcns_day, use_apr_day, na_road_cd, na_main_bun, bylot_cnt FROM silver.bld_title WHERE pnu = '1215013300107660000' AND is_current = 1 ORDER BY dong_nm;
