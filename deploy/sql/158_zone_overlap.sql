/* 158. 빈값 폴리곤이 세분 용도지역과 겹치나 (2026-10-19) — 읽기 전용
   ★ 겹치면 = 대분류(도시지역) 레이어가 같이 온 것 -> 화면에서 걷어낸다
   ★ 안 겹치면 = 용도지역 미지정 영역 -> EMPTY 로 적어야 한다
   이 둘은 화면에서 해야 할 말이 정반대다. 추측으로 고르지 않는다. */
SET NOCOUNT ON;
DECLARE @g geometry, @a FLOAT;
SELECT TOP 1 @g = geom, @a = geom.STArea()
  FROM silver.land_use_zone
 WHERE is_current = 1 AND LTRIM(ISNULL(uname,'')) = '' AND sigg_name = N'성북구';

PRINT '--- 성북구 빈값 폴리곤 vs 성북구 세분 용도지역 ---';
SELECT TOP 10 z.uname,
       세분면적 = CAST(z.geom.STArea()*1e6 AS DECIMAL(12,2)),
       겹침면적 = CAST(z.geom.STIntersection(@g).STArea()*1e6 AS DECIMAL(12,2)),
       덮임비율 = CAST(100.0 * z.geom.STIntersection(@g).STArea()
                     / NULLIF(z.geom.STArea(),0) AS DECIMAL(5,1))
  FROM silver.land_use_zone z
 WHERE z.is_current = 1 AND z.sigg_name = N'성북구'
   AND LTRIM(ISNULL(z.uname,'')) <> '' AND z.geom IS NOT NULL
 ORDER BY z.geom.STArea() DESC;

PRINT '';
PRINT '--- 시군구별 구역 수 (빈값이 왜 7개 구에만 있나) ---';
SELECT 시군구 = sigg_name, 구역 = COUNT(*),
       빈값 = SUM(CASE WHEN LTRIM(ISNULL(uname,''))='' THEN 1 ELSE 0 END),
       면적합km2 = CAST(SUM(area_m2_approx)/1000000 AS DECIMAL(10,2))
  FROM silver.land_use_zone WHERE is_current = 1
 GROUP BY sigg_name ORDER BY COUNT(*) DESC;
