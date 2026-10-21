/* 171. 단지 x 상권 피처 뷰 (2026-10-19)

   ★ 반드시 complex_id 로 걸러서 쓴다
     뷰 안에 STDistance 가 있다. 안 거르면 단지 전부 x 점포 전부를 잰다 -
     11-41 에서 v_complex_zone 을 안 걸렀다가 10분 넘게 돌았다. 같은 함정이다.

   ★ 거리는 미터다 (geography). 300/500/1000 을 그대로 쓴다.

   ★ 두 가지를 구분해서 낸다
     · 반경 안 점포  = '주변 상권'  (거리로 잰다)
     · 단지 땅 위 점포 = '단지내상가' (PNU 로 **코드 조인**한다)
     섞으면 안 된다. 앞은 입지고 뒤는 그 단지의 일부다.
*/
IF OBJECT_ID('gold.v_complex_poi') IS NOT NULL DROP VIEW gold.v_complex_poi;
GO
CREATE VIEW gold.v_complex_poi
AS
SELECT c.complex_id,
       s.bizes_id, s.bizes_nm,
       s.inds_lcls_cd, s.inds_lcls_nm, s.inds_mcls_cd, s.inds_mcls_nm,
       s.inds_scls_nm, s.pnu, s.bld_mng_no, s.bld_nm, s.flr_no,
       dist_m = s.geog.STDistance(geography::Point(c.centroid_lat, c.centroid_lng, 4326)),
       /* 이 단지 땅 위인가 — 거리와 **다른 축**이다 */
       on_site = CASE WHEN EXISTS (SELECT 1 FROM gold.complex_pnu cp
                                    WHERE cp.complex_id = c.complex_id AND cp.pnu = s.pnu)
                      THEN 1 ELSE 0 END
  FROM gold.complex c
  JOIN silver.semas_store s
    ON s.is_current = 1 AND s.geog IS NOT NULL
   AND s.geog.STDistance(geography::Point(c.centroid_lat, c.centroid_lng, 4326)) <= 1000
 WHERE c.is_active = 1 AND c.centroid_lat IS NOT NULL;
GO

PRINT '--- 확인: 장위동·수색동 300세대+ ---';
SELECT TOP 10 단지 = LEFT(c.complex_nm, 22),
       [300m] = SUM(CASE WHEN v.dist_m <= 300 THEN 1 ELSE 0 END),
       [500m] = SUM(CASE WHEN v.dist_m <= 500 THEN 1 ELSE 0 END),
       [1000m] = COUNT(*),
       음식500 = SUM(CASE WHEN v.dist_m <= 500 AND v.inds_lcls_cd = 'I2' THEN 1 ELSE 0 END),
       업종수500 = COUNT(DISTINCT CASE WHEN v.dist_m <= 500 THEN v.inds_mcls_cd END),
       단지내상가 = SUM(v.on_site)
  FROM gold.complex c
  JOIN gold.v_complex_poi v ON v.complex_id = c.complex_id
 WHERE c.has_recap = 1 AND c.hhld_cnt_sum >= 500
   AND (c.rep_plat_plc LIKE N'%장위동%' OR c.rep_plat_plc LIKE N'%수색동%')
 GROUP BY c.complex_nm ORDER BY SUM(CASE WHEN v.dist_m <= 300 THEN 1 ELSE 0 END) DESC;
