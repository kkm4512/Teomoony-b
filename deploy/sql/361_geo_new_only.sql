/* 361 새로 생긴 단지(자리 아직 없음)만 자리 잡기 (2026-10-27)
   사장님 "단지 추가됐다는데 홈 단지 수는 그대로 · 지도 검색하면 자료 없음".
   ★ gold_nation 은 268 시군구를 다 돈 뒤에야 usp_refresh_complex_geo(전체)를 부른다 — 그 전엔 새 단지에 좌표가 없어 지도 마커 · 서비스DB 층에 안 뜬다.
   ★ 계산은 324 usp_refresh_complex_geo 와 같다(단지 필지의 bbox · 가운데 · 공시지가 평균). 대상만 '좌표 없는 지금 단지' 로 좁혀
     돌고 있는 시군구 단지 만들기와 잠금 다툼을 줄인다. 주소로 자리 잡기(324 juso)는 끝에 전체 한 번 그대로 돈다. */
SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#t') IS NOT NULL DROP TABLE #t;
SELECT complex_id INTO #t FROM gold.complex WITH (NOLOCK) WHERE centroid_lat IS NULL AND merged_into IS NULL;
CREATE UNIQUE CLUSTERED INDEX x ON #t (complex_id);
IF OBJECT_ID('tempdb..#g') IS NOT NULL DROP TABLE #g;
SELECT cp.complex_id,
       MIN(p.bbox_minx) AS minx, MIN(p.bbox_miny) AS miny, MAX(p.bbox_maxx) AS maxx, MAX(p.bbox_maxy) AS maxy,
       AVG(p.jiga) AS jiga_avg, COUNT(p.pnu) AS hit
INTO #g
FROM #t t JOIN gold.complex_pnu cp ON cp.complex_id = t.complex_id
JOIN silver.cadastral_parcel p ON p.pnu = cp.pnu AND p.is_current = 1
GROUP BY cp.complex_id;
CREATE UNIQUE CLUSTERED INDEX x ON #g (complex_id);
DECLARE @n INT = 0, @lo INT = 0, @hi INT;
WHILE 1 = 1
BEGIN
    SELECT @hi = MAX(complex_id) FROM (SELECT TOP 20000 complex_id FROM #g WHERE complex_id > @lo ORDER BY complex_id) z;
    IF @hi IS NULL BREAK;
    UPDATE c
       SET c.bbox_minx = g.minx, c.bbox_miny = g.miny, c.bbox_maxx = g.maxx, c.bbox_maxy = g.maxy,
           c.centroid_lng = CAST((g.minx + g.maxx) / 2 AS DECIMAL(10,7)),
           c.centroid_lat = CAST((g.miny + g.maxy) / 2 AS DECIMAL(10,7)),
           c.jiga_avg = g.jiga_avg, c.parcel_hit = g.hit, c.updated_at = SYSDATETIME()
      FROM gold.complex c JOIN #g g ON g.complex_id = c.complex_id
     WHERE g.complex_id > @lo AND g.complex_id <= @hi;
    SET @n += @@ROWCOUNT; SET @lo = @hi; SET @hi = NULL;
END
SELECT 대상 = (SELECT COUNT(*) FROM #t), 자리잡음 = @n, 필지없음 = (SELECT COUNT(*) FROM #t) - (SELECT COUNT(*) FROM #g);
