/* 143_fp_after : 성북 필지 적재 뒤 건물 외곽선 회수 (읽기 전용) 2026-10-18 */
USE Teomoony;
GO
SET NOCOUNT ON;
GO
PRINT '--- 1. 150세대+ 단지의 외곽선 상태 (공간 교차 기준) ---';
WITH c AS (
  SELECT c.complex_id, c.sigungu_cd,
         fp = (SELECT COUNT(DISTINCT f.bd_mgt_sn)
                 FROM gold.complex_pnu cp
                 JOIN silver.cadastral_parcel p ON p.pnu=cp.pnu AND p.is_current=1 AND p.geom IS NOT NULL
                 JOIN silver.building_footprint f ON f.is_current=1 AND f.geom IS NOT NULL
                  AND f.bbox_minx<=p.bbox_maxx AND f.bbox_maxx>=p.bbox_minx
                  AND f.bbox_miny<=p.bbox_maxy AND f.bbox_maxy>=p.bbox_miny
                  AND f.geom.STIntersects(p.geom)=1
                WHERE cp.complex_id=c.complex_id),
         pc = (SELECT COUNT(*) FROM gold.complex_pnu cp
                JOIN silver.cadastral_parcel p ON p.pnu=cp.pnu AND p.is_current=1
               WHERE cp.complex_id=c.complex_id)
    FROM gold.complex c
   WHERE c.sigungu_cd IN ('11110','11290','11380') AND c.hhld_cnt_sum>=150)
SELECT 시군구 = ISNULL(sigungu_cd, N'합계'),
       단지수 = COUNT(*),
       외곽선있음 = SUM(CASE WHEN fp>0 THEN 1 ELSE 0 END),
       필지없음 = SUM(CASE WHEN pc=0 THEN 1 ELSE 0 END),
       필지는있는데외곽선0 = SUM(CASE WHEN pc>0 AND fp=0 THEN 1 ELSE 0 END)
  FROM c GROUP BY sigungu_cd WITH ROLLUP;
PRINT '  (적재 전: 314단지 중 외곽선 120 / 필지없음 110 / 필지는있는데0 84)';
GO
PRINT '--- 2. 성북 큰 단지들 ---';
SELECT TOP 14 c.complex_nm, c.hhld_cnt_sum,
       외곽선 = (SELECT COUNT(DISTINCT f.bd_mgt_sn)
                  FROM gold.complex_pnu cp
                  JOIN silver.cadastral_parcel p ON p.pnu=cp.pnu AND p.is_current=1 AND p.geom IS NOT NULL
                  JOIN silver.building_footprint f ON f.is_current=1 AND f.geom IS NOT NULL
                   AND f.bbox_minx<=p.bbox_maxx AND f.bbox_maxx>=p.bbox_minx
                   AND f.bbox_miny<=p.bbox_maxy AND f.bbox_maxy>=p.bbox_miny
                   AND f.geom.STIntersects(p.geom)=1
                 WHERE cp.complex_id=c.complex_id)
  FROM gold.complex c
 WHERE c.sigungu_cd='11290' AND c.hhld_cnt_sum>=700
 ORDER BY c.hhld_cnt_sum DESC;
GO

PRINT '--- 3. 정릉동 bbox 가 유별난가 (에러 원인 확인) ---';
SELECT lawd = LEFT(pnu,10),
       폭도 = CAST(MAX(bbox_maxx)-MIN(bbox_minx) AS DECIMAL(10,5)),
       높이도 = CAST(MAX(bbox_maxy)-MIN(bbox_miny) AS DECIMAL(10,5)),
       필지 = COUNT(*),
       건물 = (SELECT COUNT(*) FROM silver.building_footprint f
                WHERE f.is_current=1 AND LEFT(f.pnu,10)=LEFT(p.pnu,10))
  FROM silver.cadastral_parcel p
 WHERE is_current=1 AND LEFT(pnu,5)='11290'
 GROUP BY LEFT(pnu,10) ORDER BY 폭도 DESC;
GO
