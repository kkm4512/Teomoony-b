SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT j = (SELECT TOP 5 h.호PK, h.complex_id, c.complex_nm, a.main_purps_nm, c.hhld_cnt_sum, c.trade_cnt
  FROM silver.bld_expos_pubuse_area a JOIN gold.v_complex_ho h ON h.호PK = a.mgm_bldrgst_pk
  JOIN gold.complex c ON c.complex_id = h.complex_id AND c.sigungu_cd = '11620' AND c.hhld_cnt_sum > 5 AND c.trade_cnt > 20
 WHERE a.is_current = 1 AND a.expos_pubuse_gb_cd = '1' AND a.main_purps_nm LIKE N'%근린생활%'
 FOR JSON PATH);
