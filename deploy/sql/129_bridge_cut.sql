/* 129_bridge_cut : 다리를 믿어도 되는 세대수 선은 어디인가 (읽기 전용) 2026-10-18
   128 에서 PNU 와 다리가 둘 다 될 때 일치 348 / 어긋남 25 였다.
   어긋난 것들의 세대수가 33·39·42·34 로 작다 - 작은 수는 한 법정동에
   여럿이라 우연히 걸린다. 구간별로 갈라 선을 찾는다. */
USE Teomoony;
GO
SET NOCOUNT ON;
GO
IF OBJECT_ID('tempdb..#p') IS NOT NULL DROP TABLE #p;
SELECT a.mgm_pmsrgst_pk, a.hhld_cnt, a.bld_nm, a.arch_gb_nm,
       pnu_cid = (SELECT TOP 1 cp.complex_id FROM gold.complex_pnu cp WHERE cp.pnu = a.pnu),
       n1 = (SELECT COUNT(*) FROM gold.complex c
              WHERE c.sigungu_cd=a.sigungu_cd AND c.bjdong_cd=a.bjdong_cd
                AND c.hhld_cnt_sum = a.hhld_cnt),
       c1 = (SELECT TOP 1 c.complex_id FROM gold.complex c
              WHERE c.sigungu_cd=a.sigungu_cd AND c.bjdong_cd=a.bjdong_cd
                AND c.hhld_cnt_sum = a.hhld_cnt)
  INTO #p FROM silver.arch_permit a
 WHERE a.is_current = 1 AND a.hhld_cnt >= 30;
GO
PRINT '--- 세대수 구간별 : 다리가 유일할 때 PNU 와 일치하나 ---';
SELECT 구간 = CASE WHEN hhld_cnt < 50 THEN N'30~49'
                   WHEN hhld_cnt < 100 THEN N'50~99'
                   WHEN hhld_cnt < 150 THEN N'100~149'
                   WHEN hhld_cnt < 300 THEN N'150~299'
                   WHEN hhld_cnt < 600 THEN N'300~599'
                   ELSE N'600+' END,
       대상 = COUNT(*),
       다리유일 = SUM(CASE WHEN n1=1 THEN 1 ELSE 0 END),
       둘다됨 = SUM(CASE WHEN n1=1 AND pnu_cid IS NOT NULL THEN 1 ELSE 0 END),
       일치 = SUM(CASE WHEN n1=1 AND pnu_cid IS NOT NULL AND pnu_cid=c1 THEN 1 ELSE 0 END),
       어긋남 = SUM(CASE WHEN n1=1 AND pnu_cid IS NOT NULL AND pnu_cid<>c1 THEN 1 ELSE 0 END),
       새로열림 = SUM(CASE WHEN n1=1 AND pnu_cid IS NULL THEN 1 ELSE 0 END)
  FROM #p
 GROUP BY CASE WHEN hhld_cnt < 50 THEN N'30~49'
               WHEN hhld_cnt < 100 THEN N'50~99'
               WHEN hhld_cnt < 150 THEN N'100~149'
               WHEN hhld_cnt < 300 THEN N'150~299'
               WHEN hhld_cnt < 600 THEN N'300~599'
               ELSE N'600+' END
 ORDER BY MIN(hhld_cnt);
GO
PRINT '--- 150세대 이상만 보면 ---';
SELECT 둘다됨 = SUM(CASE WHEN n1=1 AND pnu_cid IS NOT NULL THEN 1 ELSE 0 END),
       일치   = SUM(CASE WHEN n1=1 AND pnu_cid IS NOT NULL AND pnu_cid=c1 THEN 1 ELSE 0 END),
       어긋남 = SUM(CASE WHEN n1=1 AND pnu_cid IS NOT NULL AND pnu_cid<>c1 THEN 1 ELSE 0 END),
       새로열림 = SUM(CASE WHEN n1=1 AND pnu_cid IS NULL THEN 1 ELSE 0 END)
  FROM #p WHERE hhld_cnt >= 150;
GO
PRINT '--- 150세대 이상에서 어긋난 것이 있으면 전부 ---';
SELECT p.mgm_pmsrgst_pk, p.bld_nm, p.hhld_cnt, p.arch_gb_nm,
       PNU단지 = (SELECT complex_nm FROM gold.complex c WHERE c.complex_id=p.pnu_cid),
       다리단지 = (SELECT complex_nm FROM gold.complex c WHERE c.complex_id=p.c1)
  FROM #p p WHERE p.hhld_cnt >= 150 AND p.n1=1 AND p.pnu_cid IS NOT NULL AND p.pnu_cid<>p.c1;
GO
