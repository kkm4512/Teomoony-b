/* 149. bld_cnt 가 화면과 다른 범위를 잰다 (2026-10-18) — 읽기 전용
   ★ gold.usp_refresh_complex_building 은 아직 f.pnu = cp.pnu (PNU 동일) 다.
     화면(server.js)은 11-26 에서 **공간교차**로 바꿨다. 한쪽만 고쳤다.
     그래서 '건물이 붙은 단지 N/M' 요약이 실제보다 적게 나온다.
   ★ 여기서는 **고치지 않고 범위만 잰다.** */
SET NOCOUNT ON;

PRINT '--- A. 총괄표제부 단지: bld_cnt vs 공간교차 실측 ---';
WITH c AS (
  SELECT c.complex_id, c.sigungu_cd, bc = ISNULL(c.bld_cnt, 0)
    FROM gold.complex c
   WHERE c.is_active = 1 AND c.has_recap = 1
     AND EXISTS (SELECT 1 FROM gold.complex_pnu p WHERE p.complex_id = c.complex_id)
), m AS (
  SELECT c.*, sp = (SELECT COUNT(DISTINCT f.bd_mgt_sn)
                      FROM gold.complex_pnu cp
                      JOIN silver.cadastral_parcel p
                        ON p.pnu = cp.pnu AND p.is_current = 1 AND p.geom IS NOT NULL
                      JOIN silver.building_footprint f
                        ON f.is_current = 1 AND f.geom IS NOT NULL
                       AND f.bbox_minx <= p.bbox_maxx AND f.bbox_maxx >= p.bbox_minx
                       AND f.bbox_miny <= p.bbox_maxy AND f.bbox_maxy >= p.bbox_miny
                       AND f.geom.STIntersects(p.geom) = 1
                     WHERE cp.complex_id = c.complex_id)
    FROM c
)
SELECT 구 = sigungu_cd, 단지 = COUNT(*),
       bld_cnt있음 = SUM(CASE WHEN bc > 0 THEN 1 ELSE 0 END),
       실측있음    = SUM(CASE WHEN sp > 0 THEN 1 ELSE 0 END),
       거짓0       = SUM(CASE WHEN bc = 0 AND sp > 0 THEN 1 ELSE 0 END),
       진짜0       = SUM(CASE WHEN bc = 0 AND sp = 0 THEN 1 ELSE 0 END),
       수가다름    = SUM(CASE WHEN bc <> sp THEN 1 ELSE 0 END)
  FROM m GROUP BY sigungu_cd ORDER BY sigungu_cd;

PRINT '';
PRINT '--- B. 응암동: bld_cnt 0 인 단지에 실측을 붙인다 ---';
SELECT c.complex_id, 단지명 = LEFT(c.complex_nm, 24),
       주소 = LEFT(ISNULL(c.rep_plat_plc, ''), 34),
       동수 = c.dong_cnt, 세대 = c.hhld_cnt_sum,
       bld_cnt = ISNULL(c.bld_cnt, 0),
       필지geom = (SELECT COUNT(*) FROM gold.complex_pnu cp
                     JOIN silver.cadastral_parcel p ON p.pnu = cp.pnu AND p.is_current = 1
                    WHERE cp.complex_id = c.complex_id AND p.geom IS NOT NULL),
       실측건물 = (SELECT COUNT(DISTINCT f.bd_mgt_sn)
                     FROM gold.complex_pnu cp
                     JOIN silver.cadastral_parcel p
                       ON p.pnu = cp.pnu AND p.is_current = 1 AND p.geom IS NOT NULL
                     JOIN silver.building_footprint f
                       ON f.is_current = 1 AND f.geom IS NOT NULL
                      AND f.bbox_minx <= p.bbox_maxx AND f.bbox_maxx >= p.bbox_minx
                      AND f.bbox_miny <= p.bbox_maxy AND f.bbox_maxy >= p.bbox_miny
                      AND f.geom.STIntersects(p.geom) = 1
                    WHERE cp.complex_id = c.complex_id)
  FROM gold.complex c
 WHERE c.is_active = 1 AND c.has_recap = 1
   AND c.rep_plat_plc LIKE N'%응암동%'
   AND ISNULL(c.bld_cnt, 0) = 0
 ORDER BY c.hhld_cnt_sum DESC;

PRINT '';
PRINT '--- C. 그래도 실측 0 인 큰 단지 (세대 300+) ---';
SELECT TOP 30 c.complex_id, 단지명 = LEFT(c.complex_nm, 24),
       구 = c.sigungu_cd, 주소 = LEFT(ISNULL(c.rep_plat_plc, ''), 34),
       동수 = c.dong_cnt, 세대 = c.hhld_cnt_sum, PNU수 = c.pnu_cnt,
       필지적재 = (SELECT COUNT(*) FROM gold.complex_pnu cp
                     JOIN silver.cadastral_parcel p ON p.pnu = cp.pnu AND p.is_current = 1
                    WHERE cp.complex_id = c.complex_id)
  FROM gold.complex c
 WHERE c.is_active = 1 AND c.has_recap = 1 AND c.hhld_cnt_sum >= 300
   AND NOT EXISTS (SELECT 1
                     FROM gold.complex_pnu cp
                     JOIN silver.cadastral_parcel p
                       ON p.pnu = cp.pnu AND p.is_current = 1 AND p.geom IS NOT NULL
                     JOIN silver.building_footprint f
                       ON f.is_current = 1 AND f.geom IS NOT NULL
                      AND f.bbox_minx <= p.bbox_maxx AND f.bbox_maxx >= p.bbox_minx
                      AND f.bbox_miny <= p.bbox_maxy AND f.bbox_maxy >= p.bbox_miny
                      AND f.geom.STIntersects(p.geom) = 1
                    WHERE cp.complex_id = c.complex_id)
 ORDER BY c.hhld_cnt_sum DESC;
