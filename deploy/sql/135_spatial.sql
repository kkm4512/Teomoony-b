/* 135_spatial : 공간 교차로 외곽선을 붙일 수 있나 (읽기 전용) 2026-10-18
   PNU 로는 60%(190/314)가 빈다. 허가 PNU 4건, 부속지번 0건으로는 못 메운다.
   남은 길은 **단지 필지 폴리곤 ∩ 건물 외곽선** 공간 교차다.
   그 길이 열리려면 두 가지가 필요하다: (1) 그 단지에 필지 폴리곤이 있을 것
   (2) 이 서버에서 공간 함수를 쓸 수 있을 것. 둘 다 확인한다. */
USE Teomoony;
GO
SET NOCOUNT ON;
GO
PRINT '--- 1. 필지 폴리곤 테이블 찾기 ---';
SELECT TABLE_SCHEMA, TABLE_NAME FROM INFORMATION_SCHEMA.TABLES
 WHERE TABLE_NAME LIKE '%parcel%' OR TABLE_NAME LIKE '%jijeok%' OR TABLE_NAME LIKE '%필지%'
    OR TABLE_NAME LIKE '%land%';
GO
PRINT '--- 2. 공간 함수가 되나 ---';
BEGIN TRY
  DECLARE @g geometry = geometry::STGeomFromText('POLYGON((0 0,1 0,1 1,0 1,0 0))', 0);
  PRINT '  geometry 사용 가능. 면적=' + CAST(@g.STArea() AS VARCHAR(20));
END TRY
BEGIN CATCH
  PRINT '  geometry 못 씀: ' + ERROR_MESSAGE();
END CATCH
GO
PRINT '--- 3. 외곽선 geojson 이 어떻게 저장돼 있나 ---';
SELECT TOP 2 LEN(geojson) AS 길이, LEFT(geojson, 160) AS 앞부분
  FROM silver.building_footprint WHERE is_current=1 AND geojson IS NOT NULL;
GO
