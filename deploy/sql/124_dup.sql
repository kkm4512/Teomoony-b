USE Teomoony;
GO
SET NOCOUNT ON;
GO
PRINT '--- 1. 전유가 여러 행인 호 - 무엇이 다른가 ---';
WITH d AS (SELECT mgm_bldrgst_pk FROM silver.bld_expos_pubuse_area
            WHERE is_current=1 AND expos_pubuse_gb_cd='1'
            GROUP BY mgm_bldrgst_pk HAVING COUNT(*)>1)
SELECT TOP 20 a.mgm_bldrgst_pk, e.dong_nm, e.ho_nm,
       a.flr_gb_cd, a.flr_no, a.main_purps_nm, a.strct_nm,
       a.area, a.seg_cnt
  FROM d JOIN silver.bld_expos_pubuse_area a
         ON a.mgm_bldrgst_pk = d.mgm_bldrgst_pk AND a.is_current=1
        AND a.expos_pubuse_gb_cd='1'
  LEFT JOIN silver.bld_expos e ON e.mgm_bldrgst_pk = a.mgm_bldrgst_pk AND e.is_current=1
 ORDER BY a.mgm_bldrgst_pk, a.flr_no;
GO

PRINT '--- 2. 그런 호가 몇이고, 층이 갈리나 용도가 갈리나 ---';
WITH d AS (SELECT mgm_bldrgst_pk, n=COUNT(*),
                  층종류=COUNT(DISTINCT CAST(flr_no AS VARCHAR(10))),
                  용도종류=COUNT(DISTINCT main_purps_cd),
                  구조종류=COUNT(DISTINCT strct_cd)
             FROM silver.bld_expos_pubuse_area
            WHERE is_current=1 AND expos_pubuse_gb_cd='1'
            GROUP BY mgm_bldrgst_pk HAVING COUNT(*)>1)
SELECT 갈린기준 = CASE WHEN 층종류 > 1 AND 용도종류 = 1 AND 구조종류 = 1 THEN N'층만 다름(복층 추정)'
                       WHEN 용도종류 > 1 THEN N'용도가 다름'
                       WHEN 구조종류 > 1 THEN N'구조가 다름'
                       ELSE N'그 외' END,
       호수 = COUNT(*), 행합 = SUM(n)
  FROM d GROUP BY CASE WHEN 층종류 > 1 AND 용도종류 = 1 AND 구조종류 = 1 THEN N'층만 다름(복층 추정)'
                       WHEN 용도종류 > 1 THEN N'용도가 다름'
                       WHEN 구조종류 > 1 THEN N'구조가 다름'
                       ELSE N'그 외' END;
GO

PRINT '--- 3. 길음동 대장단지 PNU (합필 확인, 컬럼명 고침) ---';
SELECT c.complex_nm, cp.pnu, c.hhld_cnt_sum
  FROM gold.complex c JOIN gold.complex_pnu cp ON cp.complex_id = c.complex_id
 WHERE cp.pnu LIKE '1129013400%' AND c.hhld_cnt_sum >= 300
 ORDER BY cp.pnu;
PRINT '  청약홈은 길음동 542-1 (본번 00542) 이라고 했다.';
GO
