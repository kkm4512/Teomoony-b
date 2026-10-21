/* 147_ep_gap : 은평도 같은 bbox 초과 문제인가 (읽기 전용) 2026-10-18 */
USE Teomoony;
GO
SET NOCOUNT ON;
GO
PRINT '--- 은평/종로 법정동별 필지 vs 건물 + bbox 면적 ---';
SELECT lawd = LEFT(p.pnu,10), 법정동 = MAX(l.emd_nm),
       필지 = COUNT(*),
       건물 = (SELECT COUNT(*) FROM silver.building_footprint f
                WHERE f.is_current=1 AND LEFT(f.pnu,10)=LEFT(p.pnu,10)),
       km2 = CAST((MAX(p.bbox_maxx)-MIN(p.bbox_minx))*88.0
                 *(MAX(p.bbox_maxy)-MIN(p.bbox_miny))*111.0 AS DECIMAL(8,1))
  FROM silver.cadastral_parcel p
  LEFT JOIN meta.lawd_code l ON l.lawd_cd = LEFT(p.pnu,10)
 WHERE p.is_current=1 AND LEFT(p.pnu,5) IN ('11380','11110')
 GROUP BY LEFT(p.pnu,10)
HAVING (MAX(p.bbox_maxx)-MIN(p.bbox_minx))*88.0*(MAX(p.bbox_maxy)-MIN(p.bbox_miny))*111.0 > 8
    OR (SELECT COUNT(*) FROM silver.building_footprint f
         WHERE f.is_current=1 AND LEFT(f.pnu,10)=LEFT(p.pnu,10)) = 0
 ORDER BY km2 DESC;
PRINT '  (10km2 를 넘으면 VWorld 가 BOX 질의를 거절한다 - 조용히 수신 0 이 된다)';
GO
PRINT '--- 외곽선 0 인 은평 단지는 어느 법정동인가 ---';
WITH c AS (
  SELECT c.complex_id, c.sigungu_cd, c.bjdong_cd, c.hhld_cnt_sum,
         fp = (SELECT COUNT(DISTINCT f.bd_mgt_sn)
                 FROM gold.complex_pnu cp
                 JOIN silver.cadastral_parcel p ON p.pnu=cp.pnu AND p.is_current=1 AND p.geom IS NOT NULL
                 JOIN silver.building_footprint f ON f.is_current=1 AND f.geom IS NOT NULL
                  AND f.bbox_minx<=p.bbox_maxx AND f.bbox_maxx>=p.bbox_minx
                  AND f.bbox_miny<=p.bbox_maxy AND f.bbox_maxy>=p.bbox_miny
                  AND f.geom.STIntersects(p.geom)=1
                WHERE cp.complex_id=c.complex_id)
    FROM gold.complex c WHERE c.sigungu_cd='11380' AND c.hhld_cnt_sum>=150)
SELECT lawd = sigungu_cd+bjdong_cd, 법정동 = MAX(l.emd_nm),
       외곽선0단지 = COUNT(*), 세대합 = SUM(hhld_cnt_sum)
  FROM c LEFT JOIN meta.lawd_code l ON l.lawd_cd = c.sigungu_cd+c.bjdong_cd
 WHERE fp = 0 GROUP BY sigungu_cd+bjdong_cd ORDER BY COUNT(*) DESC;
GO
