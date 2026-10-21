/* 130_bridge_rule : 다리의 최종 규칙을 확정한다 (읽기 전용) 2026-10-18
   129 에서 150세대+ 어긋남 14건이 전부 용도변경/대수선이었다(대일빌딩·피카디리플러스).
   신축으로 좁히면 어떻게 되나. */
USE Teomoony;
GO
SET NOCOUNT ON;
GO
IF OBJECT_ID('tempdb..#p') IS NOT NULL DROP TABLE #p;
SELECT a.mgm_pmsrgst_pk, a.hhld_cnt, a.bld_nm, a.arch_gb_nm, a.use_apr_day,
       pnu_cid = (SELECT TOP 1 cp.complex_id FROM gold.complex_pnu cp WHERE cp.pnu=a.pnu),
       n1 = (SELECT COUNT(*) FROM gold.complex c
              WHERE c.sigungu_cd=a.sigungu_cd AND c.bjdong_cd=a.bjdong_cd
                AND c.hhld_cnt_sum = a.hhld_cnt),
       c1 = (SELECT TOP 1 c.complex_id FROM gold.complex c
              WHERE c.sigungu_cd=a.sigungu_cd AND c.bjdong_cd=a.bjdong_cd
                AND c.hhld_cnt_sum = a.hhld_cnt)
  INTO #p FROM silver.arch_permit a
 WHERE a.is_current=1 AND a.hhld_cnt >= 30;
GO
PRINT '--- 1. 신축만, 세대수 구간별 ---';
SELECT 구간 = CASE WHEN hhld_cnt<50 THEN N'30~49' WHEN hhld_cnt<100 THEN N'50~99'
                   WHEN hhld_cnt<150 THEN N'100~149' WHEN hhld_cnt<300 THEN N'150~299'
                   ELSE N'300+' END,
       다리유일 = SUM(CASE WHEN n1=1 THEN 1 ELSE 0 END),
       일치 = SUM(CASE WHEN n1=1 AND pnu_cid IS NOT NULL AND pnu_cid=c1 THEN 1 ELSE 0 END),
       어긋남 = SUM(CASE WHEN n1=1 AND pnu_cid IS NOT NULL AND pnu_cid<>c1 THEN 1 ELSE 0 END),
       새로열림 = SUM(CASE WHEN n1=1 AND pnu_cid IS NULL THEN 1 ELSE 0 END)
  FROM #p WHERE arch_gb_nm = N'신축'
 GROUP BY CASE WHEN hhld_cnt<50 THEN N'30~49' WHEN hhld_cnt<100 THEN N'50~99'
               WHEN hhld_cnt<150 THEN N'100~149' WHEN hhld_cnt<300 THEN N'150~299'
               ELSE N'300+' END
 ORDER BY MIN(hhld_cnt);
GO
PRINT '--- 2. 확정 후보 규칙: 신축 + 150세대+ + 다리유일 ---';
SELECT 대상 = COUNT(*),
       일치 = SUM(CASE WHEN pnu_cid IS NOT NULL AND pnu_cid=c1 THEN 1 ELSE 0 END),
       어긋남 = SUM(CASE WHEN pnu_cid IS NOT NULL AND pnu_cid<>c1 THEN 1 ELSE 0 END),
       새로열림 = SUM(CASE WHEN pnu_cid IS NULL THEN 1 ELSE 0 END)
  FROM #p WHERE arch_gb_nm=N'신축' AND hhld_cnt>=150 AND n1=1;
GO
PRINT '--- 3. 그 규칙으로 새로 붙는 허가 전부 ---';
SELECT p.hhld_cnt, 허가명 = p.bld_nm, p.use_apr_day,
       새로붙는단지 = (SELECT complex_nm FROM gold.complex c WHERE c.complex_id=p.c1)
  FROM #p p
 WHERE p.arch_gb_nm=N'신축' AND p.hhld_cnt>=150 AND p.n1=1 AND p.pnu_cid IS NULL
 ORDER BY p.hhld_cnt DESC;
GO
