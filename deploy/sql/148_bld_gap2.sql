/* 148. 외곽선이 안 붙은 단지 추적 (2026-10-18)
   ★ 읽기 전용이다. 쓰기·DDL 없음.
   ★ 두 가지를 가른다 -
     (1) bld_cnt 가 0  : 적재 요약이 0 이라고 적어 둔 것
     (2) 공간교차 실측 0: 화면이 실제로 쓰는 경로(server.js 와 같은 조인)
     둘이 다르면 bld_cnt 가 낡은 것이고, 같으면 진짜 건물이 없는 것이다. */
SET NOCOUNT ON;

PRINT '--- A. 구 x 총괄표제부 별 커버리지 (bld_cnt 기준) ---';
SELECT 시군구 = c.sigungu_cd, 총괄 = c.has_recap,
       단지 = COUNT(*),
       외곽선 = SUM(CASE WHEN ISNULL(c.bld_cnt,0) > 0 THEN 1 ELSE 0 END),
       없음  = SUM(CASE WHEN ISNULL(c.bld_cnt,0) = 0 THEN 1 ELSE 0 END)
  FROM gold.complex c
 WHERE c.is_active = 1
   AND EXISTS (SELECT 1 FROM gold.complex_pnu p WHERE p.complex_id = c.complex_id)
 GROUP BY c.sigungu_cd, c.has_recap
 ORDER BY c.sigungu_cd, c.has_recap;

PRINT '';
PRINT '--- B. 총괄표제부 단지 중 외곽선 0 (실측까지 같이) ---';
SELECT TOP 40
       c.complex_id, 단지명 = c.complex_nm,
       구 = c.sigungu_cd, 동코드 = c.bjdong_cd,
       주소 = LEFT(ISNULL(c.rep_plat_plc, ''), 40),
       동수 = c.dong_cnt, 세대 = c.hhld_cnt_sum, PNU수 = c.pnu_cnt,
       bld_cnt = ISNULL(c.bld_cnt, 0),
       필지적재 = (SELECT COUNT(*) FROM gold.complex_pnu cp
                     JOIN silver.cadastral_parcel p ON p.pnu = cp.pnu AND p.is_current = 1
                    WHERE cp.complex_id = c.complex_id),
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
   AND ISNULL(c.bld_cnt, 0) = 0
   AND EXISTS (SELECT 1 FROM gold.complex_pnu p WHERE p.complex_id = c.complex_id)
 ORDER BY c.sigungu_cd, c.complex_id;

PRINT '';
PRINT '--- C. 응암동 단지 전부 (12단지 재확인) ---';
SELECT TOP 40
       c.complex_id, 단지명 = c.complex_nm,
       주소 = LEFT(ISNULL(c.rep_plat_plc, ''), 40),
       동수 = c.dong_cnt, 세대 = c.hhld_cnt_sum,
       bld_cnt = ISNULL(c.bld_cnt, 0),
       필지geom = (SELECT COUNT(*) FROM gold.complex_pnu cp
                     JOIN silver.cadastral_parcel p ON p.pnu = cp.pnu AND p.is_current = 1
                    WHERE cp.complex_id = c.complex_id AND p.geom IS NOT NULL)
  FROM gold.complex c
 WHERE c.is_active = 1 AND c.has_recap = 1
   AND c.rep_plat_plc LIKE N'%응암동%'
 ORDER BY c.complex_nm;
