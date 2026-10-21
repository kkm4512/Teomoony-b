/* 134_fp_via_pms : 허가가 PNU 번역기가 되나 (읽기 전용) 2026-10-18
   DMC 롯데캐슬: 대장 단지 PNU=417, 그런데 **허가도 외곽선도 361-10** 이다.
   대장만 다른 번지를 쓴다. 그렇다면
       단지 -> (세대수 다리) -> 허가 -> 허가의 PNU -> 외곽선
   으로 외곽선이 붙을 수 있다. 8개 단지 전부에서 되는지 본다. */
USE Teomoony;
GO
SET NOCOUNT ON;
GO
PRINT '--- 1. 다리로 붙은 8개 단지 : 대장 PNU vs 허가 PNU vs 외곽선 ---';
SELECT c.complex_nm, c.hhld_cnt_sum,
       단지PNU = (SELECT TOP 1 cp.pnu FROM gold.complex_pnu cp WHERE cp.complex_id=c.complex_id ORDER BY cp.pnu),
       허가PNU = a.pnu,
       같은가 = CASE WHEN EXISTS (SELECT 1 FROM gold.complex_pnu cp
                                   WHERE cp.complex_id=c.complex_id AND cp.pnu=a.pnu)
                     THEN N'같음' ELSE N'다름' END,
       단지PNU외곽선 = (SELECT COUNT(*) FROM gold.complex_pnu cp
                         JOIN silver.building_footprint f ON f.pnu=cp.pnu AND f.is_current=1
                        WHERE cp.complex_id=c.complex_id),
       허가PNU외곽선 = (SELECT COUNT(*) FROM silver.building_footprint f
                        WHERE f.is_current=1 AND f.pnu = a.pnu)
  FROM gold.v_complex_permit v
  JOIN gold.complex c ON c.complex_id = v.complex_id
  JOIN silver.arch_permit a ON a.mgm_pmsrgst_pk = v.mgm_pmsrgst_pk AND a.is_current=1
 WHERE v.match_by = 'HHLD'
 ORDER BY c.hhld_cnt_sum DESC;
GO

PRINT '--- 2. 전체로 넓히면? PNU 로 붙은 허가까지 포함해 외곽선 회수 ---';
WITH c AS (
  SELECT c.complex_id, c.complex_nm, c.hhld_cnt_sum,
         fp_now = (SELECT COUNT(*) FROM gold.complex_pnu cp
                    JOIN silver.building_footprint f ON f.pnu=cp.pnu AND f.is_current=1
                   WHERE cp.complex_id=c.complex_id),
         fp_pms = (SELECT COUNT(*) FROM gold.v_complex_permit v
                    JOIN silver.arch_permit a ON a.mgm_pmsrgst_pk=v.mgm_pmsrgst_pk AND a.is_current=1
                    JOIN silver.building_footprint f ON f.pnu=a.pnu AND f.is_current=1
                   WHERE v.complex_id=c.complex_id)
    FROM gold.complex c
   WHERE c.sigungu_cd IN ('11110','11290','11380') AND c.hhld_cnt_sum>=150)
SELECT 판정 = CASE WHEN fp_now>0 THEN N'지금도 외곽선 있음'
                   WHEN fp_pms>0 THEN N'★ 허가 PNU 로 새로 생김'
                   ELSE N'그래도 없음' END,
       단지수 = COUNT(*)
  FROM c
 GROUP BY CASE WHEN fp_now>0 THEN N'지금도 외곽선 있음'
                WHEN fp_pms>0 THEN N'★ 허가 PNU 로 새로 생김'
                ELSE N'그래도 없음' END
 ORDER BY 단지수 DESC;
GO

PRINT '--- 3. 부속지번(atch) 을 쓰면 더 회수되나 ---';
WITH c AS (
  SELECT c.complex_id, c.hhld_cnt_sum,
         fp_now = (SELECT COUNT(*) FROM gold.complex_pnu cp
                    JOIN silver.building_footprint f ON f.pnu=cp.pnu AND f.is_current=1
                   WHERE cp.complex_id=c.complex_id),
         fp_atch = (SELECT COUNT(*) FROM gold.complex_bld cb
                     JOIN silver.bld_atch_jibun j ON j.mgm_bldrgst_pk=cb.mgm_bldrgst_pk AND j.is_current=1
                     JOIN silver.building_footprint f ON f.pnu=j.atch_pnu AND f.is_current=1
                    WHERE cb.complex_id=c.complex_id)
    FROM gold.complex c
   WHERE c.sigungu_cd IN ('11110','11290','11380') AND c.hhld_cnt_sum>=150)
SELECT 판정 = CASE WHEN fp_now>0 THEN N'지금도 있음'
                   WHEN fp_atch>0 THEN N'★ 부속지번으로 새로 생김'
                   ELSE N'그래도 없음' END,
       단지수 = COUNT(*)
  FROM c
 GROUP BY CASE WHEN fp_now>0 THEN N'지금도 있음'
                WHEN fp_atch>0 THEN N'★ 부속지번으로 새로 생김'
                ELSE N'그래도 없음' END
 ORDER BY 단지수 DESC;
GO
