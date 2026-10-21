/* 192. 노선명 분열이 화면에 실제로 영향을 주나 (2026-10-19) 읽기 전용 */
SET NOCOUNT ON;
PRINT '--- 같은 역이 같은 노선번호인데 이름이 둘로 나뉜 경우 ---';
SELECT sttn_nm, line_cd, 이름수 = COUNT(DISTINCT line_nm),
       이름들 = STRING_AGG('[' + line_nm + ']', ' ')
  FROM silver.subway_station WHERE is_current = 1
 GROUP BY sttn_nm, line_cd HAVING COUNT(DISTINCT line_nm) > 1;

PRINT '';
PRINT '--- 우리 단지 1.5km 안에 실제로 등장하는 노선명 ---';
SELECT 노선 = '[' + line_nm + ']', 등장역 = COUNT(DISTINCT sttn_nm)
  FROM (SELECT DISTINCT s.line_nm, s.sttn_nm
          FROM silver.subway_station s
         WHERE s.is_current = 1 AND s.geog IS NOT NULL
           AND EXISTS (SELECT 1 FROM gold.complex c
                        WHERE c.is_active = 1 AND c.centroid_lat IS NOT NULL
                          AND s.geog.STDistance(geography::Point(c.centroid_lat, c.centroid_lng, 4326)) <= 1500)) t
 GROUP BY line_nm ORDER BY line_nm;

PRINT '';
PRINT '--- 1.5km 안에 역이 없는 단지는 어디인가 (법정동 상위 10) ---';
SELECT TOP 10 동 = MAX(c.rep_plat_plc), 단지 = COUNT(*)
  FROM gold.complex c
  LEFT JOIN (SELECT DISTINCT complex_id FROM gold.v_complex_subway) z ON z.complex_id = c.complex_id
 WHERE c.is_active = 1 AND c.centroid_lat IS NOT NULL AND z.complex_id IS NULL
 GROUP BY LEFT(c.rep_pnu, 10) ORDER BY COUNT(*) DESC;
