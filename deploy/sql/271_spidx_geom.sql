/* 271. 공간색인 — 건물 외곽선 · 필지 (2026-10-21, 사장님 승인 15:05)
   ★ 왜
     silver.building_footprint 에 공간색인이 없었다(CONTEXT 11-113). bbox 네 칸에도 색인이 없어
     필지 x 외곽선 공간조인이 표를 훑는다. 그래서
       - gold.usp_refresh_complex_building 이 3시간 20분(11-136 ④)
       - /api/complexes/:id/buildings 가 최대 17초(11-134)
     footprint 적재(서울 전체 building)가 10-21 14:49 에 끝나서 이제 만들 수 있다.
     남은 적재(공시가격 hsprc · 학원 좌표)는 이 두 표를 안 쓴다.
   ★ 경계상자는 **전국**으로 잡는다(124~132 · 33~39). 지금은 서울·안양뿐이지만
     전국으로 넓힐 때 색인을 다시 만들지 않게. AUTO_GRID 8단계라 칸이 충분히 잘다.
   ★ MAXDOP 4 — 공시가격 적재와 CPU 를 나눠 쓴다.
   ★ 다시 돌려도 된다(IF NOT EXISTS). 지우는 문장 없음. */
SET NOCOUNT ON;
GO
DECLARE @t DATETIME2 = SYSDATETIME();
IF NOT EXISTS (SELECT 1 FROM sys.spatial_indexes WHERE name = 'sx_building_footprint_geom')
    CREATE SPATIAL INDEX sx_building_footprint_geom
        ON silver.building_footprint (geom)
        USING GEOMETRY_AUTO_GRID
        WITH (BOUNDING_BOX = (124, 33, 132, 39), CELLS_PER_OBJECT = 16, MAXDOP = 4);
PRINT CONCAT('footprint 공간색인 (초) = ', DATEDIFF(SECOND, @t, SYSDATETIME()));
GO
DECLARE @t DATETIME2 = SYSDATETIME();
IF NOT EXISTS (SELECT 1 FROM sys.spatial_indexes WHERE name = 'sx_cadastral_parcel_geom')
    CREATE SPATIAL INDEX sx_cadastral_parcel_geom
        ON silver.cadastral_parcel (geom)
        USING GEOMETRY_AUTO_GRID
        WITH (BOUNDING_BOX = (124, 33, 132, 39), CELLS_PER_OBJECT = 16, MAXDOP = 4);
PRINT CONCAT('parcel 공간색인 (초) = ', DATEDIFF(SECOND, @t, SYSDATETIME()));
GO
SELECT 표 = OBJECT_NAME(object_id), 이름 = name FROM sys.spatial_indexes
 WHERE name IN ('sx_building_footprint_geom', 'sx_cadastral_parcel_geom');
GO
PRINT '271 완료';
