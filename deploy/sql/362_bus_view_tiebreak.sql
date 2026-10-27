/* 362 gold.v_complex_bus — 같은 ARS 묶음 안에서 거리가 같으면 정류장ID(stop_no) 순으로 고정 (2026-10-27)
   사장님 "순서 없이 보여주는 것들은 ID 로 · 가시성을 생각하면 가나다 순". 전엔 같은 거리의 두 정류장 중 어느 것이 남을지 정해져 있지 않았다.
   ★ 그 밖은 지금 정의(OBJECT_DEFINITION) 그대로. */
CREATE OR ALTER VIEW gold.v_complex_bus AS
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
                             geography::Point(c.centroid_lat, c.centroid_lng, 4326)), b.stop_no)   /* 362: 같은 거리면 정류장ID 순(고정) */
      FROM gold.complex c
      JOIN silver.bus_stop b
        ON b.is_current = 1 AND b.geog IS NOT NULL
       AND b.geog.STDistance(geography::Point(c.centroid_lat, c.centroid_lng, 4326)) <= 500
     WHERE c.is_active = 1 AND c.centroid_lat IS NOT NULL) t
 WHERE rn = 1;
GO
