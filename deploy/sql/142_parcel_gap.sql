/* 142_parcel_gap : 필지 폴리곤이 어느 법정동에서 비나 (읽기 전용) 2026-10-18
   공간 교차로 외곽선을 잇게 됐는데(11-26) 110개 단지는 **땅이 없어서** 못 한다.
   load_cadastral.py 는 인자 없이 돌리면 단지가 참조하는 법정동 전부를 받는다.
   그러면 왜 비었나 - 안 돌린 법정동인지, 돌렸는데 안 온 것인지 가른다. */
USE Teomoony;
GO
SET NOCOUNT ON;
GO
PRINT '--- 1. 단지가 참조하는 법정동 vs 필지가 있는 법정동 ---';
WITH need AS (
  SELECT DISTINCT lawd = LEFT(cp.pnu,10) FROM gold.complex_pnu cp
   WHERE LEFT(cp.pnu,5) IN ('11110','11290','11380')),
have AS (
  SELECT lawd = LEFT(pnu,10), n = COUNT(*) FROM silver.cadastral_parcel
   WHERE is_current=1 GROUP BY LEFT(pnu,10))
SELECT 판정 = CASE WHEN h.n IS NULL THEN N'필지 0 (안 받아왔다)'
                   WHEN h.n < 100  THEN N'필지 100개 미만 (부분?)'
                   ELSE N'있음' END,
       법정동수 = COUNT(*)
  FROM need n LEFT JOIN have h ON h.lawd = n.lawd
 GROUP BY CASE WHEN h.n IS NULL THEN N'필지 0 (안 받아왔다)'
               WHEN h.n < 100  THEN N'필지 100개 미만 (부분?)'
               ELSE N'있음' END;
GO

PRINT '--- 2. 필지가 비어 있는 법정동 전부 (단지 수와 함께) ---';
WITH need AS (
  SELECT lawd = LEFT(cp.pnu,10), 단지수 = COUNT(DISTINCT cp.complex_id)
    FROM gold.complex_pnu cp
   WHERE LEFT(cp.pnu,5) IN ('11110','11290','11380')
   GROUP BY LEFT(cp.pnu,10))
SELECT n.lawd, 법정동 = l.emd_nm, n.단지수,
       필지 = ISNULL((SELECT COUNT(*) FROM silver.cadastral_parcel p
                       WHERE p.is_current=1 AND LEFT(p.pnu,10)=n.lawd), 0)
  FROM need n LEFT JOIN meta.lawd_code l ON l.lawd_cd = n.lawd
 WHERE NOT EXISTS (SELECT 1 FROM silver.cadastral_parcel p
                    WHERE p.is_current=1 AND LEFT(p.pnu,10)=n.lawd)
 ORDER BY n.단지수 DESC;
GO

PRINT '--- 3. 외곽선 없는 150세대+ 단지 110개는 어느 법정동인가 ---';
WITH c AS (
  SELECT c.complex_id, c.complex_nm, c.sigungu_cd, c.bjdong_cd, c.hhld_cnt_sum,
         pc = (SELECT COUNT(*) FROM gold.complex_pnu cp
                JOIN silver.cadastral_parcel p ON p.pnu=cp.pnu AND p.is_current=1
               WHERE cp.complex_id=c.complex_id)
    FROM gold.complex c
   WHERE c.sigungu_cd IN ('11110','11290','11380') AND c.hhld_cnt_sum>=150)
SELECT lawd = c.sigungu_cd + c.bjdong_cd, 법정동 = MAX(l.emd_nm),
       단지수 = COUNT(*), 세대합 = SUM(c.hhld_cnt_sum)
  FROM c LEFT JOIN meta.lawd_code l ON l.lawd_cd = c.sigungu_cd + c.bjdong_cd
 WHERE c.pc = 0
 GROUP BY c.sigungu_cd + c.bjdong_cd ORDER BY COUNT(*) DESC;
GO
