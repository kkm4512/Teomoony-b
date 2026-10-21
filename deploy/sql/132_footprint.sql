/* ============================================================
   132_footprint : 건물 외곽선이 왜 비나 (읽기 전용)  2026-10-18

   화면에 `건물 외곽선 0` 이 뜬다. 원인 후보가 셋이고 **아직 모른다**:
     (1) 그 법정동의 외곽선을 아예 안 받아왔다              -> SCOPE
     (2) 받아왔는데 재개발 신축이 아직 반영 안 됐다(4-18)   -> 데이터 시점
     (3) 받아왔고 건물도 있는데 PNU 가 안 맞는다(합필)      -> 조인 문제
   셋은 화면에 적을 말이 다르다. 숫자로 가른다.
   ============================================================ */
USE Teomoony;
GO
SET NOCOUNT ON;
GO

PRINT '--- 1. 외곽선 적재 범위 (법정동별) ---';
SELECT lawd = LEFT(pnu,10), 외곽선수 = COUNT(*)
  FROM silver.building_footprint
 WHERE is_current = 1 AND pnu IS NOT NULL
   AND LEFT(pnu,5) IN ('11110','11290','11380')
 GROUP BY LEFT(pnu,10) ORDER BY LEFT(pnu,10);
GO

PRINT '--- 2. 단지별 외곽선 유무 : 법정동에 외곽선이 있나 / 그 단지에 있나 ---';
WITH c AS (
  SELECT c.complex_id, c.complex_nm, c.hhld_cnt_sum,
         lawd = c.sigungu_cd + c.bjdong_cd,
         fp = (SELECT COUNT(*) FROM gold.complex_pnu cp
                JOIN silver.building_footprint f ON f.pnu = cp.pnu AND f.is_current=1
               WHERE cp.complex_id = c.complex_id)
    FROM gold.complex c
   WHERE c.sigungu_cd IN ('11110','11290','11380') AND c.hhld_cnt_sum >= 150)
SELECT 판정 = CASE
         WHEN fp > 0 THEN N'외곽선 있음'
         WHEN NOT EXISTS (SELECT 1 FROM silver.building_footprint f
                           WHERE f.is_current=1 AND LEFT(f.pnu,10) = c.lawd)
              THEN N'그 법정동을 아직 안 받아왔다 (SCOPE)'
         ELSE N'법정동엔 있는데 이 단지엔 없다' END,
       단지수 = COUNT(*)
  FROM c
 GROUP BY CASE
         WHEN fp > 0 THEN N'외곽선 있음'
         WHEN NOT EXISTS (SELECT 1 FROM silver.building_footprint f
                           WHERE f.is_current=1 AND LEFT(f.pnu,10) = c.lawd)
              THEN N'그 법정동을 아직 안 받아왔다 (SCOPE)'
         ELSE N'법정동엔 있는데 이 단지엔 없다' END
 ORDER BY 단지수 DESC;
GO

PRINT '--- 3. 새로 다리를 놓은 8개 단지는? ---';
SELECT c.complex_nm, c.hhld_cnt_sum,
       외곽선 = (SELECT COUNT(*) FROM gold.complex_pnu cp
                  JOIN silver.building_footprint f ON f.pnu=cp.pnu AND f.is_current=1
                 WHERE cp.complex_id=c.complex_id),
       법정동외곽선 = (SELECT COUNT(*) FROM silver.building_footprint f
                       WHERE f.is_current=1 AND LEFT(f.pnu,10)=c.sigungu_cd+c.bjdong_cd)
  FROM gold.complex c
 WHERE c.complex_id IN (SELECT DISTINCT complex_id FROM gold.v_complex_permit WHERE match_by='HHLD')
 ORDER BY c.hhld_cnt_sum DESC;
GO

PRINT '--- 4. DMC 롯데캐슬(수색동 417) 근처 외곽선은 무엇인가 ---';
SELECT TOP 15 f.buld_nm, f.pnu, f.gro_flo_co, f.area_m2_approx
  FROM silver.building_footprint f
 WHERE f.is_current=1 AND LEFT(f.pnu,10) = '1138010100'
 ORDER BY f.area_m2_approx DESC;
GO
