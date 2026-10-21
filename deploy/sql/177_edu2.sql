/* 177. 학원 묶음을 쪼개고, 요가/필라테스를 운동으로 옮긴다 (2026-10-19) — 읽기 전용
   ★ P1 18개 소분류를 전부 어딘가로 보낸다. 남는 것 없이. */
SET NOCOUNT ON;
DECLARE @cid INT = (SELECT TOP 1 complex_id FROM gold.complex
                     WHERE complex_nm LIKE N'%녹번역e편한세상캐슬%' AND is_active = 1);
PRINT '--- 대상 단지 ---';
SELECT complex_id, complex_nm FROM gold.complex WHERE complex_id = @cid;

PRINT '';
PRINT '--- 제안한 묶음대로 세어본다 (500m / 1km) ---';
WITH v AS (SELECT * FROM gold.v_complex_poi WHERE complex_id = @cid),
g AS (
  SELECT dist_m, grp = CASE
      WHEN v.inds_scls_nm = N'입시·교과학원'            THEN N'09 입시·보습학원'
      WHEN v.inds_scls_nm = N'외국어학원'               THEN N'10 영어·외국어'
      WHEN v.inds_scls_nm IN (N'음악학원', N'미술학원', N'태권도/무술학원',
                              N'기타 예술/스포츠 교육기관') THEN N'11 예체능학원'
      WHEN v.inds_scls_nm = N'요가/필라테스 학원'        THEN N'13 헬스·요가'
      WHEN v.inds_scls_nm = N'헬스장'                   THEN N'13 헬스·요가'
      WHEN v.inds_scls_nm IN (N'컴퓨터 학원', N'전문자격/고시학원',
                              N'레크리에이션 교육기관', N'그 외 기타 교육기관',
                              N'사회교육시설', N'청소년 수련시설', N'운전학원')
                                                        THEN N'12 그 외 학원'
      WHEN v.inds_lcls_cd = 'P1'                        THEN N'__ 성인·직업(묶음에서 뺀다)'
      END
    FROM v)
SELECT 묶음 = grp,
       [500m] = SUM(CASE WHEN dist_m <= 500 THEN 1 ELSE 0 END),
       [1km]  = COUNT(*)
  FROM g WHERE grp IS NOT NULL GROUP BY grp ORDER BY grp;

PRINT '';
PRINT '--- 지금 화면의 학원·교육(P1 전체) 과 비교 ---';
SELECT [지금_P1전체_500m] = SUM(CASE WHEN dist_m <= 500 THEN 1 ELSE 0 END)
  FROM gold.v_complex_poi WHERE complex_id = @cid AND inds_lcls_cd = 'P1';

PRINT '';
PRINT '--- P1 소분류가 전부 배정됐는지 (전국 기준, 미배정 = 성인·직업만 남아야) ---';
SELECT 소분류 = inds_scls_nm, 전체 = COUNT(*)
  FROM silver.semas_store WHERE is_current = 1 AND inds_lcls_cd = 'P1'
   AND inds_scls_nm NOT IN (N'입시·교과학원', N'외국어학원', N'음악학원', N'미술학원',
        N'태권도/무술학원', N'기타 예술/스포츠 교육기관', N'요가/필라테스 학원',
        N'컴퓨터 학원', N'전문자격/고시학원', N'레크리에이션 교육기관',
        N'그 외 기타 교육기관', N'사회교육시설', N'청소년 수련시설', N'운전학원')
 GROUP BY inds_scls_nm ORDER BY COUNT(*) DESC;

PRINT '';
PRINT '--- 헬스장이 어느 대분류에 있나 (P1 과 겹치지 않는지) ---';
SELECT inds_lcls_cd, inds_lcls_nm, inds_mcls_nm, 전체 = COUNT(*)
  FROM silver.semas_store WHERE is_current = 1 AND inds_scls_nm = N'헬스장'
 GROUP BY inds_lcls_cd, inds_lcls_nm, inds_mcls_nm;
