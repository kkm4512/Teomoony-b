SET NOCOUNT ON; SET XACT_ABORT ON;
IF OBJECT_ID('tempdb..#pk') IS NOT NULL DROP TABLE #pk;
SELECT TOP 3 pk = mgm_bldrgst_pk INTO #pk FROM silver.bld_title WHERE is_current = 1 AND sigungu_cd = '12150' ORDER BY mgm_bldrgst_pk;
DECLARE @cl NVARCHAR(MAX) = (SELECT STRING_AGG('[' + name + ']', ', ') WITHIN GROUP (ORDER BY column_id) FROM sys.columns WHERE object_id = OBJECT_ID('silver.bld_title') AND is_identity = 0);
SELECT 전_지금 = COUNT(*), 전_해시 = CHECKSUM_AGG(CHECKSUM(mgm_bldrgst_pk, bld_nm, hhld_cnt, tot_area, use_apr_day, main_purps_nm)) FROM silver.bld_title WHERE is_current = 1 AND mgm_bldrgst_pk IN (SELECT pk FROM #pk);
BEGIN TRAN;
UPDATE s SET is_current = 0, valid_to = SYSDATETIME() FROM silver.bld_title s WHERE s.is_current = 1 AND s.mgm_bldrgst_pk IN (SELECT pk FROM #pk);
DECLARE @a INT = @@ROWCOUNT;
EXEC (N'INSERT INTO silver.bld_title (' + @cl + N') SELECT ' + @cl + N' FROM hubv.bld_title WHERE mgm_bldrgst_pk IN (SELECT pk FROM #pk)');
SELECT 닫음 = @a, 후_지금 = COUNT(*), 후_해시 = CHECKSUM_AGG(CHECKSUM(mgm_bldrgst_pk, bld_nm, hhld_cnt, tot_area, use_apr_day, main_purps_nm)),
       후_닫힌줄 = (SELECT COUNT(*) FROM silver.bld_title WHERE is_current = 0 AND mgm_bldrgst_pk IN (SELECT pk FROM #pk))
  FROM silver.bld_title WHERE is_current = 1 AND mgm_bldrgst_pk IN (SELECT pk FROM #pk);
ROLLBACK;
SELECT 되돌린뒤_지금 = COUNT(*), 되돌린뒤_닫힌줄 = (SELECT COUNT(*) FROM silver.bld_title WHERE is_current = 0 AND mgm_bldrgst_pk IN (SELECT pk FROM #pk))
  FROM silver.bld_title WHERE is_current = 1 AND mgm_bldrgst_pk IN (SELECT pk FROM #pk);
