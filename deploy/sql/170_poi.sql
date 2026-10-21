/* 170. 단지별 상권 피처가 떨어지나 (2026-10-19) — 읽기 전용
   ★ geography 라 STDistance 가 **미터**로 나온다. 300/500/1000 을 그대로 쓴다. */
SET NOCOUNT ON;
PRINT '--- A. 적재 ---';
SELECT 점포 = COUNT(*), PNU있음 = SUM(CASE WHEN pnu IS NOT NULL THEN 1 ELSE 0 END),
       건물번호있음 = SUM(CASE WHEN bld_mng_no IS NOT NULL THEN 1 ELSE 0 END),
       법정동 = COUNT(DISTINCT ldong_cd)
  FROM silver.semas_store WHERE is_current = 1;

PRINT '';
PRINT '--- B. 단지별 반경 피처 (300/500/1000m, 음식점, 업종 다양성) ---';
SELECT TOP 12
       단지 = LEFT(c.complex_nm, 22), 세대 = c.hhld_cnt_sum,
       [300m] = SUM(CASE WHEN d <= 300 THEN 1 ELSE 0 END),
       [500m] = SUM(CASE WHEN d <= 500 THEN 1 ELSE 0 END),
       [1000m] = COUNT(*),
       음식500 = SUM(CASE WHEN d <= 500 AND s.inds_lcls_cd = 'I2' THEN 1 ELSE 0 END),
       소매500 = SUM(CASE WHEN d <= 500 AND s.inds_lcls_cd = 'G2' THEN 1 ELSE 0 END),
       업종수500 = COUNT(DISTINCT CASE WHEN d <= 500 THEN s.inds_mcls_cd END)
  FROM gold.complex c
  CROSS APPLY (
    SELECT s.inds_lcls_cd, s.inds_mcls_cd,
           d = s.geog.STDistance(geography::Point(c.centroid_lat, c.centroid_lng, 4326))
      FROM silver.semas_store s
     WHERE s.is_current = 1 AND s.geog IS NOT NULL
       AND s.geog.STDistance(geography::Point(c.centroid_lat, c.centroid_lng, 4326)) <= 1000
  ) s
 WHERE c.is_active = 1 AND c.has_recap = 1 AND c.hhld_cnt_sum >= 300
   AND (c.rep_plat_plc LIKE N'%장위동%' OR c.rep_plat_plc LIKE N'%수색동%')
 GROUP BY c.complex_nm, c.hhld_cnt_sum
 ORDER BY c.hhld_cnt_sum DESC;

PRINT '';
PRINT '--- C. ★ PNU 로 직접 붙는 점포 (단지 땅 위의 상가) ---';
SELECT TOP 10 단지 = LEFT(c.complex_nm, 22), 점포 = COUNT(*),
       예시 = MIN(s.bizes_nm)
  FROM gold.complex c
  JOIN gold.complex_pnu cp ON cp.complex_id = c.complex_id
  JOIN silver.semas_store s ON s.pnu = cp.pnu AND s.is_current = 1
 WHERE c.is_active = 1 AND c.has_recap = 1
 GROUP BY c.complex_nm ORDER BY COUNT(*) DESC;
