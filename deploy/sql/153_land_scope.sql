/* 153. 토지 쪽에 지금 뭐가 들어 있나 (2026-10-18) — 읽기 전용 */
SET NOCOUNT ON;
PRINT '--- land_char ---';
SELECT 행 = COUNT(*), PNU = COUNT(DISTINCT pnu),
       용도지역있음 = SUM(CASE WHEN prpos_area1_nm IS NOT NULL THEN 1 ELSE 0 END),
       공시지가있음 = SUM(CASE WHEN pblntf_pclnd IS NOT NULL THEN 1 ELSE 0 END)
  FROM silver.land_char WHERE is_current = 1;

PRINT '';
PRINT '--- 용도지역 분포 (상위) ---';
SELECT TOP 15 용도지역 = prpos_area1_nm, 필지 = COUNT(*)
  FROM silver.land_char WHERE is_current = 1 AND prpos_area1_nm IS NOT NULL
 GROUP BY prpos_area1_nm ORDER BY COUNT(*) DESC;

PRINT '';
PRINT '--- 우리 단지 중 토지특성이 붙은 비율 ---';
WITH c AS (
  SELECT c.complex_id,
         hit = CASE WHEN EXISTS (SELECT 1 FROM gold.complex_pnu cp
                 JOIN silver.land_char l ON l.pnu = cp.pnu AND l.is_current = 1
                WHERE cp.complex_id = c.complex_id) THEN 1 ELSE 0 END
    FROM gold.complex c WHERE c.is_active = 1 AND c.has_recap = 1
)
SELECT 총괄단지 = COUNT(*), 토지특성있음 = SUM(hit) FROM c;

PRINT '';
PRINT '--- cadastral_parcel 의 지가 ---';
SELECT 필지 = COUNT(*), 지가있음 = SUM(CASE WHEN jiga IS NOT NULL THEN 1 ELSE 0 END)
  FROM silver.cadastral_parcel WHERE is_current = 1;
