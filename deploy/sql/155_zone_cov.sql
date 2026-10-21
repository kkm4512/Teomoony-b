/* 155. 용도지역이 단지에 얼마나 붙나 (2026-10-18) — 읽기 전용 */
SET NOCOUNT ON;
PRINT '--- A. 적재 현황 ---';
SELECT 구역 = COUNT(*), 시군구 = COUNT(DISTINCT sigg_name),
       geom있음 = SUM(CASE WHEN geom IS NOT NULL THEN 1 ELSE 0 END)
  FROM silver.land_use_zone WHERE is_current = 1;

PRINT '';
PRINT '--- B. 총괄표제부 단지 중 용도지역이 붙는 비율 ---';
WITH c AS (
  SELECT c.complex_id, c.sigungu_cd,
         hit = CASE WHEN EXISTS (
           SELECT 1 FROM gold.complex_pnu cp
             JOIN silver.cadastral_parcel p
               ON p.pnu = cp.pnu AND p.is_current = 1 AND p.geom IS NOT NULL
             JOIN silver.land_use_zone z
               ON z.is_current = 1 AND z.geom IS NOT NULL
              AND z.bbox_minx <= p.bbox_maxx AND z.bbox_maxx >= p.bbox_minx
              AND z.bbox_miny <= p.bbox_maxy AND z.bbox_maxy >= p.bbox_miny
              AND z.geom.STIntersects(p.geom) = 1
            WHERE cp.complex_id = c.complex_id) THEN 1 ELSE 0 END
    FROM gold.complex c
   WHERE c.is_active = 1 AND c.has_recap = 1
)
SELECT 구 = sigungu_cd, 단지 = COUNT(*), 용도지역있음 = SUM(hit),
       비율 = CAST(100.0 * SUM(hit) / COUNT(*) AS DECIMAL(5,1))
  FROM c GROUP BY sigungu_cd ORDER BY sigungu_cd;

PRINT '';
PRINT '--- C. 아는 단지 몇 개 (비중까지) ---';
SELECT TOP 20 단지 = LEFT(c.complex_nm, 22), 용도지역 = v.uname,
       비중 = CAST(100.0 * SUM(v.xarea) OVER (PARTITION BY v.complex_id, v.uname)
                   / SUM(v.xarea) OVER (PARTITION BY v.complex_id) AS DECIMAL(5,1))
  FROM gold.v_complex_zone v
  JOIN gold.complex c ON c.complex_id = v.complex_id
 WHERE c.complex_nm LIKE N'%래미안%장위%' OR c.complex_nm LIKE N'%장위자이%'
    OR c.complex_nm LIKE N'%녹번역e편한세상%'
 ORDER BY c.complex_nm, 비중 DESC;
