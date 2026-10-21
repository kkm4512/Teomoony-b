/* 229_vlrat_verify : 굳힌 표와 뷰를 **전수 대조**한다 (2026-10-20) 읽기만 한다.
   ★ EXCEPT 를 쓴다 - NULL = NULL 을 제대로 같다고 본다(= 로 비교하면 전부 '다름'이 된다). */
USE Teomoony;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 표 = (SELECT COUNT(*) FROM gold.bld_vlrat),
       뷰 = (SELECT COUNT(*) FROM gold.v_bld_vlrat);
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 다른건수 = COUNT(*)
  FROM gold.bld_vlrat f
  JOIN gold.v_bld_vlrat v ON v.mgm_bldrgst_pk = f.mgm_bldrgst_pk
 WHERE EXISTS (
         SELECT f.상위percent, f.용도지역, f.바구니수, f.단계, f.넓은비교, f.사유
         EXCEPT
         SELECT v.상위percent, v.용도지역, v.바구니수, v.단계, v.넓은비교, v.사유);
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
PRINT '--- 바구니 큰 것 다섯 ---';
SELECT TOP 5 용도지역, 단계, 넓은비교, 바구니수 = MIN(바구니수), 건수 = COUNT(*)
  FROM gold.bld_vlrat WHERE 상위percent IS NOT NULL
 GROUP BY 용도지역, 단계, 넓은비교 ORDER BY COUNT(*) DESC;
GO
