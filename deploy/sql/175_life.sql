/* 175. '생활 편의' 묶음을 만들 때 쓸 실제 소분류 이름 (2026-10-19) — 읽기 전용
   ★ 묶음을 **지어내지 않는다.** 데이터에 있는 이름에서 고른다. */
SET NOCOUNT ON;
PRINT '--- 후보 키워드에 걸리는 실제 소분류 ---';
SELECT 소분류 = inds_scls_nm, 중분류 = inds_mcls_nm, 대분류 = inds_lcls_nm, 전체 = COUNT(*)
  FROM silver.semas_store WHERE is_current = 1
   AND (inds_scls_nm LIKE N'%편의점%' OR inds_scls_nm LIKE N'%슈퍼%'
     OR inds_scls_nm LIKE N'%마트%'  OR inds_scls_nm LIKE N'%카페%'
     OR inds_scls_nm LIKE N'%커피%'  OR inds_scls_nm LIKE N'%약국%'
     OR inds_scls_nm LIKE N'%세탁%'  OR inds_scls_nm LIKE N'%미용실%'
     OR inds_scls_nm LIKE N'%빵%'    OR inds_scls_nm LIKE N'%제과%'
     OR inds_scls_nm LIKE N'%헬스%'  OR inds_scls_nm LIKE N'%체육%'
     OR inds_scls_nm LIKE N'%어린이집%' OR inds_scls_nm LIKE N'%유치원%'
     OR inds_scls_nm LIKE N'%은행%')
 GROUP BY inds_scls_nm, inds_mcls_nm, inds_lcls_nm ORDER BY COUNT(*) DESC;

PRINT '';
PRINT '--- 대분류 코드 전체 (음식/보건/교육 코드 확인) ---';
SELECT 코드 = inds_lcls_cd, 대분류 = inds_lcls_nm, 전체 = COUNT(*)
  FROM silver.semas_store WHERE is_current = 1
 GROUP BY inds_lcls_cd, inds_lcls_nm ORDER BY COUNT(*) DESC;

PRINT '';
PRINT '--- 음식 대분류 안의 중분류 (음식점 vs 주점 구분되나) ---';
SELECT 중분류 = inds_mcls_nm, 코드 = inds_mcls_cd, 전체 = COUNT(*)
  FROM silver.semas_store WHERE is_current = 1 AND inds_lcls_cd = 'I2'
 GROUP BY inds_mcls_nm, inds_mcls_cd ORDER BY COUNT(*) DESC;
