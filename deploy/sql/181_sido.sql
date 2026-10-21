/* 181. 우리 단지가 어느 시도에 있나 (2026-10-19) — 읽기 전용
   ★ TAGO 버스정류소에 **서울이 없다**(도시 138곳에 미포함, 실측).
     TAGO 가 우리에게 쓸모가 있는지부터 센다. 추측하지 않는다. */
SET NOCOUNT ON;
SELECT 시도코드 = LEFT(c.sigungu_cd, 2), 단지 = COUNT(*),
       활성 = SUM(CASE WHEN c.is_active = 1 THEN 1 ELSE 0 END),
       좌표있음 = SUM(CASE WHEN c.centroid_lat IS NOT NULL THEN 1 ELSE 0 END)
  FROM gold.complex c
 GROUP BY LEFT(c.sigungu_cd, 2) ORDER BY COUNT(*) DESC;
