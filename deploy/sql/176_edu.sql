/* 176. 학원·학교를 따로 보여주려면 (2026-10-19) — 읽기 전용
   ★ 상권 데이터에 '학교'가 있는지부터 본다. 없으면 상권으로 학교를 그릴 수 없다. */
SET NOCOUNT ON;
PRINT '--- P1(학문/교육) 중분류 전체 ---';
SELECT 중분류 = inds_mcls_nm, 코드 = inds_mcls_cd, 전체 = COUNT(*)
  FROM silver.semas_store WHERE is_current = 1 AND inds_lcls_cd = 'P1'
 GROUP BY inds_mcls_nm, inds_mcls_cd ORDER BY COUNT(*) DESC;

PRINT '';
PRINT '--- P1 소분류 상위 40 ---';
SELECT TOP 40 소분류 = inds_scls_nm, 중분류 = inds_mcls_nm, 전체 = COUNT(*)
  FROM silver.semas_store WHERE is_current = 1 AND inds_lcls_cd = 'P1'
 GROUP BY inds_scls_nm, inds_mcls_nm ORDER BY COUNT(*) DESC;

PRINT '';
PRINT '--- 이름에 학교/초등/중학/고등 들어가는 업종 (대분류 상관없이) ---';
SELECT 소분류 = inds_scls_nm, 중분류 = inds_mcls_nm, 대분류 = inds_lcls_nm, 전체 = COUNT(*)
  FROM silver.semas_store WHERE is_current = 1
   AND (inds_scls_nm LIKE N'%학교%' OR inds_scls_nm LIKE N'%초등%'
     OR inds_scls_nm LIKE N'%중학%' OR inds_scls_nm LIKE N'%고등%'
     OR inds_mcls_nm LIKE N'%학교%' OR inds_scls_nm LIKE N'%유치원%'
     OR inds_scls_nm LIKE N'%어린이집%')
 GROUP BY inds_scls_nm, inds_mcls_nm, inds_lcls_nm ORDER BY COUNT(*) DESC;

PRINT '';
PRINT '--- 상호에 "초등학교" 가 들어간 점포 10개 (값의 생김새) ---';
SELECT TOP 10 bizes_nm, inds_lcls_nm, inds_mcls_nm, inds_scls_nm
  FROM silver.semas_store WHERE is_current = 1 AND bizes_nm LIKE N'%초등학교%';
