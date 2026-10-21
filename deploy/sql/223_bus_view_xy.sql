/* ============================================================
   223_bus_view_xy : gold.v_complex_bus 에 좌표를 넣는다 (2026-10-20)

   ★ 지하철(v_complex_subway)과 학교(v_complex_school)에는 lat/lon 이 이미 있었는데
     버스만 없었다. 목록에 마우스를 올리면 지도에 점을 찍으려면 좌표가 있어야 한다.
   ★ 원본 정의를 그대로 두고 **칸만 더한다.** 행 수도 묶는 규칙도 안 바꾼다.
     (ARS 가 같으면 한 승강장 — 가장 가까운 줄 하나만 남긴다. 183 의 규칙 그대로.)
   ============================================================ */
USE Teomoony;
GO
IF OBJECT_ID('gold.v_complex_bus') IS NOT NULL DROP VIEW gold.v_complex_bus;
GO
CREATE VIEW gold.v_complex_bus AS
SELECT complex_id, stop_no, stop_nm, ars_no, city_code, mng_city_nm, lat, lon, dist_m
  FROM (
    SELECT c.complex_id, b.stop_no, b.stop_nm, b.ars_no, b.city_code, b.mng_city_nm,
           b.lat, b.lon,
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
PRINT '--- 확인: 좌표가 붙었나 / 행 수는 그대로인가 ---';
SELECT TOP 3 complex_id, stop_nm, lat, lon, 거리 = CAST(dist_m AS INT)
  FROM gold.v_complex_bus WHERE complex_id = 40866 ORDER BY dist_m;
GO
SELECT 버스_500m = COUNT(*) FROM gold.v_complex_bus WHERE complex_id = 40866;
GO
