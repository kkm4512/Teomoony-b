/* 133_fp2 : 외곽선이 0 인 단지 - 어느 쪽 PNU 가 좁은가 (읽기 전용) 2026-10-18
   외곽선은 적재돼 있고 최신이다(수색동에 e편한세상 수색 에코포레 15층이 있다).
   그런데 DMC 롯데캐슬(수색동 417)은 0 이다. 둘 중 하나다:
     (a) complex_pnu 가 대표지번 하나뿐이다  -> 부속지번(atch)으로 넓히면 된다
     (b) 외곽선이 그 건물을 다른 번지로 들고 있다
   ★ 이름 매칭은 **진단에만** 쓴다(정책 1장). */
USE Teomoony;
GO
SET NOCOUNT ON;
GO
PRINT '--- 1. 외곽선 0 인 단지의 complex_pnu 는 몇 개인가 ---';
SELECT c.complex_nm, c.hhld_cnt_sum,
       pnu수 = (SELECT COUNT(*) FROM gold.complex_pnu cp WHERE cp.complex_id=c.complex_id),
       pnu목록 = (SELECT TOP 5 STRING_AGG(cp.pnu, ' ') FROM gold.complex_pnu cp
                   WHERE cp.complex_id=c.complex_id)
  FROM gold.complex c
 WHERE c.complex_id IN (SELECT complex_id FROM gold.v_complex_permit WHERE match_by='HHLD')
 ORDER BY c.hhld_cnt_sum DESC;
GO

PRINT '--- 2. 전체: 단지당 complex_pnu 개수 분포 (150세대+) ---';
SELECT pnu수구간 = CASE WHEN n=1 THEN N'1개' WHEN n<5 THEN N'2~4개'
                        WHEN n<20 THEN N'5~19개' ELSE N'20개+' END,
       단지수 = COUNT(*),
       외곽선있음 = SUM(CASE WHEN fp>0 THEN 1 ELSE 0 END)
  FROM (SELECT c.complex_id,
               n = (SELECT COUNT(*) FROM gold.complex_pnu cp WHERE cp.complex_id=c.complex_id),
               fp = (SELECT COUNT(*) FROM gold.complex_pnu cp
                      JOIN silver.building_footprint f ON f.pnu=cp.pnu AND f.is_current=1
                     WHERE cp.complex_id=c.complex_id)
          FROM gold.complex c
         WHERE c.sigungu_cd IN ('11110','11290','11380') AND c.hhld_cnt_sum>=150) t
 GROUP BY CASE WHEN n=1 THEN N'1개' WHEN n<5 THEN N'2~4개'
               WHEN n<20 THEN N'5~19개' ELSE N'20개+' END
 ORDER BY 1;
GO

PRINT '--- 3. 수색동 417 언저리에 외곽선이 있나 (본번 0417) ---';
SELECT f.buld_nm, f.pnu, f.gro_flo_co, f.area_m2_approx
  FROM silver.building_footprint f
 WHERE f.is_current=1 AND f.pnu LIKE '1138010100%' AND SUBSTRING(f.pnu,12,4)='0417';
GO

PRINT '--- 4. ★ 진단용 이름 역추적 : DMC 롯데캐슬 건물이 어느 PNU 에 있나 ---';
SELECT TOP 10 f.buld_nm, f.pnu, f.gro_flo_co, f.area_m2_approx,
       단지붙음 = CASE WHEN EXISTS (SELECT 1 FROM gold.complex_pnu cp WHERE cp.pnu=f.pnu)
                       THEN N'Y' ELSE N'N' END
  FROM silver.building_footprint f
 WHERE f.is_current=1 AND f.buld_nm LIKE N'%롯데캐슬%' AND LEFT(f.pnu,5)='11380';
GO

PRINT '--- 5. 부속지번(atch) 축은 이 단지들에 있나 ---';
SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
 WHERE TABLE_SCHEMA='silver' AND TABLE_NAME='bld_atch_jibun' ORDER BY ORDINAL_POSITION;
GO
