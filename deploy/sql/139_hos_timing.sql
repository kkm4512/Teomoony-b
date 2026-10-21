USE Teomoony;
GO
SET NOCOUNT ON;
SET STATISTICS TIME ON;
GO
PRINT '=== 1. v_complex_ho 단독 ===';
SELECT COUNT(*) FROM gold.v_complex_ho WHERE complex_id = 103835;
GO
PRINT '=== 2. + 공시가격 뷰 조인 ===';
SELECT COUNT(*) FROM gold.v_complex_ho h
  LEFT JOIN gold.v_complex_ho_price p ON p.호PK = h.호PK
 WHERE h.complex_id = 103835;
GO
PRINT '=== 3. + 전용면적 APPLY 만 (가격 뷰 빼고) ===';
SELECT COUNT(*) FROM gold.v_complex_ho h
  OUTER APPLY (SELECT s=SUM(a2.area) FROM silver.bld_expos_pubuse_area a2
                WHERE a2.mgm_bldrgst_pk=h.호PK AND a2.is_current=1
                  AND a2.expos_pubuse_gb_cd='1') ea
 WHERE h.complex_id = 103835;
GO
PRINT '=== 4. v_complex_ho_price 전체가 얼마나 무거운가 ===';
SELECT COUNT(*) FROM gold.v_complex_ho_price;
GO
SET STATISTICS TIME OFF;
GO
