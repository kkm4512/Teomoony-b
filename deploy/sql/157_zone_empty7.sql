/* 157. 이름 없는 거대 폴리곤 7개의 정체 (2026-10-19) — 읽기 전용 */
SET NOCOUNT ON;
SELECT zone_key = LEFT(zone_key, 12),
       uname = ISNULL(NULLIF(LTRIM(uname), ''), N'(빈값)'),
       dyear, dnum, 시도 = sido_name, 시군구 = sigg_name,
       면적km2 = CAST(area_m2_approx/1000000 AS DECIMAL(10,2)),
       가로km = CAST((bbox_maxx-bbox_minx)*88 AS DECIMAL(8,2)),
       세로km = CAST((bbox_maxy-bbox_miny)*111 AS DECIMAL(8,2)),
       중심 = CONCAT(CAST(centroid_lng AS DECIMAL(9,5)), ' ', CAST(centroid_lat AS DECIMAL(9,5)))
  FROM silver.land_use_zone
 WHERE is_current = 1 AND (uname IS NULL OR LTRIM(uname) = '')
 ORDER BY area_m2_approx DESC;

PRINT '';
PRINT '--- 이름 있는 구역 중 가장 큰 것들과 비교 ---';
SELECT TOP 5 uname, 시군구 = sigg_name,
       면적km2 = CAST(area_m2_approx/1000000 AS DECIMAL(10,2))
  FROM silver.land_use_zone
 WHERE is_current = 1 AND LTRIM(ISNULL(uname,'')) <> ''
 ORDER BY area_m2_approx DESC;
