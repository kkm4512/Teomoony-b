USE Teomoony;
GO
SET NOCOUNT ON;
GO
PRINT '--- geom 컬럼 타입 ---';
SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE
  FROM INFORMATION_SCHEMA.COLUMNS
 WHERE TABLE_SCHEMA='silver'
   AND TABLE_NAME IN ('cadastral_parcel','building_footprint')
   AND COLUMN_NAME IN ('geom','geojson','bbox_minx','centroid_lat')
 ORDER BY TABLE_NAME, COLUMN_NAME;
GO
PRINT '--- geom 이 채워져 있나 ---';
SELECT 테이블=N'cadastral_parcel', 전체=COUNT(*), geom있음=SUM(CASE WHEN geom IS NOT NULL THEN 1 ELSE 0 END)
  FROM silver.cadastral_parcel WHERE is_current=1
UNION ALL
SELECT N'building_footprint', COUNT(*), SUM(CASE WHEN geom IS NOT NULL THEN 1 ELSE 0 END)
  FROM silver.building_footprint WHERE is_current=1;
GO
PRINT '--- 실제 공간 교차 시험 : DMC 롯데캐슬 필지에 들어가는 외곽선 ---';
SELECT 외곽선수 = COUNT(*)
  FROM gold.complex_pnu cp
  JOIN silver.cadastral_parcel p ON p.pnu = cp.pnu AND p.is_current=1 AND p.geom IS NOT NULL
  JOIN silver.building_footprint f ON f.is_current=1 AND f.geom IS NOT NULL
   AND f.geom.STIntersects(p.geom) = 1
 WHERE cp.complex_id = 103835;
GO
