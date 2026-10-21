/* 179. 단지 ↔ 학교 (2026-10-19)
   ★ 반드시 complex_id 로 먼저 거른 뒤 쓴다.
     STDistance 가 든 뷰를 조건 없이 조회하면 81,143개 단지를 전부 센다
     (11-44 에서 10분 넘게 돌았다). 뷰는 '재료' 지 '결과' 가 아니다.

   ★ 2km 까지만 담는다 — 초등학교 통학거리는 보통 1km 안쪽이고,
     중·고는 더 멀어도 되지만 2km 넘어가면 '주변' 이라고 부를 수 없다.

   ★ 거리는 직선거리다. 도보 거리가 아니고, **배정(학구도)은 더더욱 아니다.**
     초품아 같은 말은 거리로 정해지지 않는다 - 통학구역은 교육지원청이 정하고
     그 데이터는 여기 없다(학구도안내서비스 schoolzone.emac.kr 가 별도 출처).
     화면에 반드시 그렇게 적는다.
*/
IF OBJECT_ID('gold.v_complex_school') IS NOT NULL DROP VIEW gold.v_complex_school;
GO
CREATE VIEW gold.v_complex_school AS
SELECT c.complex_id,
       s.school_id, s.school_nm, s.school_se, s.fond_type, s.bnhh_se,
       s.lnmadr, s.rdnmadr, s.lat, s.lon,
       dist_m = s.geog.STDistance(geography::Point(c.centroid_lat, c.centroid_lng, 4326))
  FROM gold.complex c
  JOIN silver.school s
    ON s.is_current = 1 AND s.geog IS NOT NULL AND s.oper_sttus = N'운영'
   AND s.geog.STDistance(geography::Point(c.centroid_lat, c.centroid_lng, 4326)) <= 2000
 WHERE c.is_active = 1 AND c.centroid_lat IS NOT NULL;
GO
PRINT '179 완료 - gold.v_complex_school';
GO
/* 검산 — 녹번역e편한세상캐슬 */
DECLARE @cid INT = (SELECT TOP 1 complex_id FROM gold.complex
                     WHERE complex_nm LIKE N'%녹번역e편한세상캐슬%' AND is_active = 1);
WITH v AS (SELECT * FROM gold.v_complex_school WHERE complex_id = @cid)
SELECT 학교급 = school_se,
       [500m] = SUM(CASE WHEN dist_m <= 500 THEN 1 ELSE 0 END),
       [1km]  = SUM(CASE WHEN dist_m <= 1000 THEN 1 ELSE 0 END),
       [2km]  = COUNT(*), 최단m = CAST(MIN(dist_m) AS INT)
  FROM v GROUP BY school_se ORDER BY school_se;

PRINT '';
PRINT '--- 가장 가까운 5개 ---';
SELECT TOP 5 school_nm, school_se, fond_type, m = CAST(dist_m AS INT), lnmadr
  FROM gold.v_complex_school WHERE complex_id = @cid ORDER BY dist_m;
