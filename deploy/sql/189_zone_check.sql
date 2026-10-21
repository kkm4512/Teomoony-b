/* 189. 학구도 검산 — '가장 가까운 학교' 와 '배정 학교' 가 다른가 (2026-10-19) */
SET NOCOUNT ON;
PRINT '--- 녹번역e편한세상캐슬 ---';
DECLARE @cid INT = (SELECT TOP 1 complex_id FROM gold.complex
                     WHERE complex_nm LIKE N'%녹번역e편한세상캐슬%' AND is_active = 1);
DECLARE @p geometry = (SELECT geometry::Point(centroid_lng, centroid_lat, 4326)
                         FROM gold.complex WHERE complex_id = @cid);
SELECT 배정학구 = z.hakgudo_nm, 구분 = CASE z.hakgudo_gb WHEN '1' THEN N'공동' ELSE N'단독' END,
       교육지원청 = z.edu_nm
  FROM silver.school_zone z
 WHERE z.geom.STContains(@p) = 1;

PRINT '';
PRINT '--- 가장 가까운 초등학교 3곳 (거리 기준) ---';
SELECT TOP 3 school_nm, m = CAST(dist_m AS INT)
  FROM gold.v_complex_school WHERE complex_id = @cid AND school_se = N'초등학교'
 ORDER BY dist_m;

PRINT '';
PRINT '--- 세 구 전체: 단지가 학구 안에 들어가나 ---';
SELECT 단지 = COUNT(*),
       학구찾음 = SUM(CASE WHEN z.hakgudo_id IS NOT NULL THEN 1 ELSE 0 END)
  FROM gold.complex c
  OUTER APPLY (SELECT TOP 1 hakgudo_id FROM silver.school_zone z2
                WHERE z2.geom.STContains(
                        geometry::Point(c.centroid_lng, c.centroid_lat, 4326)) = 1) z
 WHERE c.is_active = 1 AND c.centroid_lat IS NOT NULL;
