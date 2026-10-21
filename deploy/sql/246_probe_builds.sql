/* builds(공간조인)가 60초를 넘기는 자리. 고치기 전에 **재고** 확인한다.
   1) building_footprint 색인 — bbox 범위조인이 탈 길이 있나, 공간색인이 있나
   2) geom 은 있는데 geojson 이 NULL 인 행이 있나
      → 있으면 _q_builds(목록)와 /buildings(지도)가 **다른 수**를 센다.
        _q_builds 주석은 "지도와 같은 기준으로 센다" 고 약속한다.
   3) footprint 전체 건수 (적재가 늘리는 중) */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* ★ COLLATE DATABASE_DEFAULT 가 필요하다. sys.indexes.type_desc 는 카탈로그
   collation 이라 i.name 과 섞으면 "Cannot resolve collation conflict" 로 터진다. */
SELECT 색인 = STRING_AGG(CAST(CONCAT(i.name, ' [', i.type_desc COLLATE DATABASE_DEFAULT, '] ', c.칸) AS NVARCHAR(MAX)), N'
')
  FROM sys.indexes i
 CROSS APPLY (SELECT 칸 = ISNULL(STRING_AGG(CAST(col.name AS NVARCHAR(MAX)), ',')
                             WITHIN GROUP (ORDER BY ic.key_ordinal), '(없음)')
                FROM sys.index_columns ic
                JOIN sys.columns col ON col.object_id = ic.object_id
                                    AND col.column_id = ic.column_id
               WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id
                 AND ic.is_included_column = 0) c
 WHERE i.object_id = OBJECT_ID('silver.building_footprint') AND i.name IS NOT NULL;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 전체 = COUNT(*),
       geom있음 = SUM(CASE WHEN geom IS NOT NULL THEN 1 ELSE 0 END),
       geom있고_geojson없음 = SUM(CASE WHEN geom IS NOT NULL AND geojson IS NULL THEN 1 ELSE 0 END)
  FROM silver.building_footprint WHERE is_current = 1;
