/* 183. 단지 ↔ 지하철역 / 버스정류장 (2026-10-19)
   ★ 반드시 complex_id 로 먼저 거르고 쓴다 (11-44 교훈).
   ★ 거리는 geography — 미터다.

   ── 지하철 ────────────────────────────────────────────
   1.5km 까지 담는다. 그 밖은 '역세권' 이라 부를 수 없다.
   ★ 한 역이 여러 노선이면 **줄이 여러 개**다(공덕 = 공항철도/5호선/6호선).
     그대로 세면 역이 세 개처럼 보인다. 화면에서 **역사명으로 묶는다.**

   ── 버스 ──────────────────────────────────────────────
   500m 까지. 버스는 걸어가는 거리라 지하철보다 짧게 잡는다.
   ★ 같은 승강장이 서울BIS/경기BIS 로 **두 줄** 올 수 있다(서울 838건 실측).
     (city_code, ars_no) 로 묶어 **대표 한 줄만** 남긴다.
     ARS 가 비어 있으면 묶을 수 없으니 그 줄은 그대로 둔다.
*/
IF OBJECT_ID('gold.v_complex_subway') IS NOT NULL DROP VIEW gold.v_complex_subway;
GO
CREATE VIEW gold.v_complex_subway AS
SELECT c.complex_id, s.sttn_nm, s.line_nm, s.line_cd, s.transfer_se,
       s.oper_nm, s.road_addr, s.lat, s.lon,
       dist_m = s.geog.STDistance(geography::Point(c.centroid_lat, c.centroid_lng, 4326))
  FROM gold.complex c
  JOIN silver.subway_station s
    ON s.is_current = 1 AND s.geog IS NOT NULL
   AND s.geog.STDistance(geography::Point(c.centroid_lat, c.centroid_lng, 4326)) <= 1500
 WHERE c.is_active = 1 AND c.centroid_lat IS NOT NULL;
GO
IF OBJECT_ID('gold.v_complex_bus') IS NOT NULL DROP VIEW gold.v_complex_bus;
GO
CREATE VIEW gold.v_complex_bus AS
SELECT complex_id, stop_no, stop_nm, ars_no, city_code, mng_city_nm, dist_m
  FROM (
    SELECT c.complex_id, b.stop_no, b.stop_nm, b.ars_no, b.city_code, b.mng_city_nm,
           dist_m = b.geog.STDistance(geography::Point(c.centroid_lat, c.centroid_lng, 4326)),
           /* ARS 가 같으면 한 승강장이다. 가장 가까운 줄 하나만 남긴다.
              ARS 가 없으면 stop_no 로 떨어뜨려 **묶지 않는다.** */
           rn = ROW_NUMBER() OVER (
                  PARTITION BY c.complex_id, b.city_code,
                               ISNULL(b.ars_no, b.stop_no)
                  ORDER BY b.geog.STDistance(
                             geography::Point(c.centroid_lat, c.centroid_lng, 4326)))
      FROM gold.complex c
      JOIN silver.bus_stop b
        ON b.is_current = 1 AND b.geog IS NOT NULL
       AND b.geog.STDistance(geography::Point(c.centroid_lat, c.centroid_lng, 4326)) <= 500
     WHERE c.is_active = 1 AND c.centroid_lat IS NOT NULL) t
 WHERE rn = 1;
GO
PRINT '183 완료 - gold.v_complex_subway / gold.v_complex_bus';
GO
/* 검산 — 녹번역e편한세상캐슬 */
DECLARE @cid INT = (SELECT TOP 1 complex_id FROM gold.complex
                     WHERE complex_nm LIKE N'%녹번역e편한세상캐슬%' AND is_active = 1);
PRINT '--- 가까운 지하철역 (역사명으로 묶어서) ---';
WITH v AS (SELECT * FROM gold.v_complex_subway WHERE complex_id = @cid)
SELECT TOP 6 역 = sttn_nm, 노선 = STRING_AGG(line_nm, ', '),
       m = CAST(MIN(dist_m) AS INT)
  FROM v GROUP BY sttn_nm ORDER BY MIN(dist_m);
