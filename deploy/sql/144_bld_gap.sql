/* 144_bld_gap : 건물 외곽선(building_footprint) 적재 범위 (읽기 전용) 2026-10-18
   필지를 다 채웠는데도 성북 129단지 중 100개가 외곽선 0 이다.
   0 인 단지가 길음동·정릉동에 몰려 있다 -> 이번엔 **건물** 쪽 범위를 본다.
   필지(cadastral_parcel)와 건물(building_footprint)은 **적재기가 다르다.** */
USE Teomoony;
GO
SET NOCOUNT ON;
GO
PRINT '--- 법정동별: 필지 vs 건물외곽선 (성북구) ---';
WITH n AS (SELECT DISTINCT lawd = LEFT(pnu,10) FROM gold.complex_pnu WHERE LEFT(pnu,5)='11290')
SELECT n.lawd, 법정동 = l.emd_nm,
       필지 = (SELECT COUNT(*) FROM silver.cadastral_parcel p
                WHERE p.is_current=1 AND LEFT(p.pnu,10)=n.lawd),
       건물 = (SELECT COUNT(*) FROM silver.building_footprint f
                WHERE f.is_current=1 AND LEFT(f.pnu,10)=n.lawd)
  FROM n LEFT JOIN meta.lawd_code l ON l.lawd_cd = n.lawd
 ORDER BY 건물, n.lawd;
GO
PRINT '--- 시군구 요약 ---';
SELECT 시군구 = LEFT(pnu,5), 건물외곽선 = COUNT(*)
  FROM silver.building_footprint WHERE is_current=1
 GROUP BY LEFT(pnu,5) ORDER BY LEFT(pnu,5);
GO
