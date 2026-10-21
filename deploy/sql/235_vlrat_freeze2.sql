/* ============================================================
   235_vlrat_freeze2 : 바구니를 나눈 분위를 다시 굳힌다 (2026-10-20)
   220 을 대체한다 — 칸에 `종류`('단지'/'건물')가 늘었다.
   ★ 열쇠는 (종류, mgm_bldrgst_pk) 다. 총괄과 표제부는 다른 대장이라
     pk 가 겹칠 일이 없어야 하지만, **없어야 한다**는 건 확인 전까지 가정이다.
     묶어서 열쇠로 두면 겹쳐도 안 깨지고, 겹치면 유니크 인덱스가 알려 준다.
   ★ 굳힌 뒤 뷰와 **전수 대조**한다(EXCEPT — NULL=NULL 을 같다고 본다).
   ============================================================ */
USE Teomoony;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
GO
IF OBJECT_ID('gold.bld_vlrat') IS NOT NULL DROP TABLE gold.bld_vlrat;
GO
SELECT 종류, mgm_bldrgst_pk, pnu, bld_nm, vl_rat, bc_rat, plat_area,
       용도지역, 단계, 상위, 바구니수, 상위percent, 넓은비교, 사유,
       굳힌때 = SYSDATETIME()
  INTO gold.bld_vlrat
  FROM gold.v_bld_vlrat;
GO
CREATE UNIQUE CLUSTERED INDEX cx_bld_vlrat ON gold.bld_vlrat (종류, mgm_bldrgst_pk);
GO
CREATE INDEX ix_bld_vlrat_pk ON gold.bld_vlrat (mgm_bldrgst_pk)
    INCLUDE (종류, 상위percent, 용도지역, 바구니수, 넓은비교, 사유);
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
PRINT '--- 굳힌 결과 ---';
SELECT 종류, 전체 = COUNT(*),
       분위있음 = SUM(CASE WHEN 상위percent IS NOT NULL THEN 1 ELSE 0 END)
  FROM gold.bld_vlrat GROUP BY 종류;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
PRINT '--- 뷰와 전수 대조 (0 이어야 한다) ---';
SELECT 다른건수 = COUNT(*)
  FROM gold.bld_vlrat f
  JOIN gold.v_bld_vlrat v
    ON v.종류 = f.종류 AND v.mgm_bldrgst_pk = f.mgm_bldrgst_pk
 WHERE EXISTS (
         SELECT f.상위percent, f.용도지역, f.바구니수, f.단계, f.넓은비교, f.사유
         EXCEPT
         SELECT v.상위percent, v.용도지역, v.바구니수, v.단계, v.넓은비교, v.사유);
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
PRINT '--- 단지 바구니 큰 것 다섯 (작은 바구니가 얼마나 되는지 본다) ---';
SELECT TOP 5 용도지역, 바구니수 = MIN(바구니수), 건수 = COUNT(*)
  FROM gold.bld_vlrat WHERE 종류 = N'단지' AND 상위percent IS NOT NULL
 GROUP BY 용도지역 ORDER BY COUNT(*) DESC;
GO
