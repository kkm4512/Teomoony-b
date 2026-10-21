/* /api/lawds 가 60초 타임아웃이다(법정동 지도가 공개 사이트에서 안 열린다).
   어디가 느린지 **쪼개서** 잰다 — 짐작으로 고치지 않는다.
     A 뷰만 (bbox 거름)
     B 뷰 + geojson 스칼라 서브쿼리  ← 엔드포인트가 하는 것
     C 뷰 전체 건수 (bbox 없이) — 뷰 자체가 무거운가
   ★ 서울 가운데 bbox 로 잰다. */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 변형='A 뷰만', 행 = COUNT(*)
  FROM gold.v_lawd_map v
 WHERE bbox_minx <= 127.1 AND bbox_maxx >= 126.9
   AND bbox_miny <= 37.65 AND bbox_maxy >= 37.5;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 변형='B 뷰+geojson', 행 = COUNT(*), 경계있음 = SUM(CASE WHEN g.geojson IS NULL THEN 0 ELSE 1 END)
  FROM gold.v_lawd_map v
 OUTER APPLY (SELECT TOP 1 geojson FROM silver.lawd_boundary b
               WHERE b.is_current = 1 AND b.lawd_cd = v.lawd_cd) g
 WHERE bbox_minx <= 127.1 AND bbox_maxx >= 126.9
   AND bbox_miny <= 37.65 AND bbox_maxy >= 37.5;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 변형='C 뷰 전체', 행 = COUNT(*) FROM gold.v_lawd_map;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* lawd_boundary 색인 — lawd_cd 로 찾는 길이 있나 */
SELECT 색인 = ISNULL(STRING_AGG(CAST(CONCAT(i.name,'[',i.type_desc COLLATE DATABASE_DEFAULT,']') AS NVARCHAR(MAX)), N', '), '(없음)')
  FROM sys.indexes i
 WHERE i.object_id = OBJECT_ID('silver.lawd_boundary') AND i.name IS NOT NULL;
