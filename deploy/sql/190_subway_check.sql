/* 190. 지하철이 정말 다 됐나 (2026-10-19) — 읽기 전용 */
SET NOCOUNT ON;
PRINT '--- 적재 전체 ---';
SELECT 현재행 = COUNT(*), 이력행 = SUM(CASE WHEN is_current = 0 THEN 1 ELSE 0 END),
       노선 = COUNT(DISTINCT line_nm), 고유역명 = COUNT(DISTINCT sttn_nm),
       좌표없음 = SUM(CASE WHEN geog IS NULL THEN 1 ELSE 0 END)
  FROM silver.subway_station;

PRINT '';
PRINT '--- is_current=0 이 왜 생겼나 (주안역 중복 흔적) ---';
SELECT line_cd, sttn_cd, sttn_nm, line_nm, is_current, valid_to
  FROM silver.subway_station WHERE is_current = 0;

PRINT '';
PRINT '--- 서울 주소 역: 노선별 ---';
SELECT line_nm, 역 = COUNT(DISTINCT sttn_nm)
  FROM silver.subway_station
 WHERE is_current = 1 AND road_addr LIKE N'서울특별시%'
 GROUP BY line_nm ORDER BY COUNT(DISTINCT sttn_nm) DESC;

PRINT '';
PRINT '--- 우리 단지 중 1.5km 안에 역이 없는 곳 ---';
SELECT 단지 = COUNT(*),
       역있음 = SUM(CASE WHEN z.complex_id IS NOT NULL THEN 1 ELSE 0 END)
  FROM gold.complex c
  LEFT JOIN (SELECT DISTINCT complex_id FROM gold.v_complex_subway) z
    ON z.complex_id = c.complex_id
 WHERE c.is_active = 1 AND c.centroid_lat IS NOT NULL;
