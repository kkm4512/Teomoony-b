/* ============================================================
   128_bridge_full : (법정동+세대수[+사용승인]) 다리를 전수로 잰다 (읽기 전용)
                     2026-10-18

   11-22 에서 14건으로 재 보니 유일 10 / 없음 4 / 모호 0 이었다.
   표본이 작다. 전수로 다시 잰다. 그리고 **진짜 검증을 같이 한다** —
   PNU 로도 붙고 다리로도 붙는 자리에서 **둘이 같은 단지를 가리키는가**.
   어긋나면 다리는 쓸 수 없다. 한 건이라도 어긋나면 그 자리부터 본다.
   ★ 아무것도 안 바꾼다.
   ============================================================ */
USE Teomoony;
GO
SET NOCOUNT ON;
GO

IF OBJECT_ID('tempdb..#p') IS NOT NULL DROP TABLE #p;
SELECT a.mgm_pmsrgst_pk, a.sigungu_cd, a.bjdong_cd, a.bld_nm,
       a.hhld_cnt, a.use_apr_day, a.arch_gb_nm, a.pnu,
       pnu_cid = (SELECT TOP 1 cp.complex_id FROM gold.complex_pnu cp WHERE cp.pnu = a.pnu),
       n1 = (SELECT COUNT(*) FROM gold.complex c
              WHERE c.sigungu_cd=a.sigungu_cd AND c.bjdong_cd=a.bjdong_cd
                AND c.hhld_cnt_sum = a.hhld_cnt),
       c1 = (SELECT TOP 1 c.complex_id FROM gold.complex c
              WHERE c.sigungu_cd=a.sigungu_cd AND c.bjdong_cd=a.bjdong_cd
                AND c.hhld_cnt_sum = a.hhld_cnt),
       /* 사용승인 연도까지 보탠 것. 단지는 동마다 승인일이 달라 범위를 갖는다. */
       n2 = (SELECT COUNT(*) FROM gold.complex c
              WHERE c.sigungu_cd=a.sigungu_cd AND c.bjdong_cd=a.bjdong_cd
                AND c.hhld_cnt_sum = a.hhld_cnt
                AND a.use_apr_day IS NOT NULL
                AND LEFT(a.use_apr_day,4) BETWEEN
                    CAST(CAST(LEFT(c.oldest_use_apr,4) AS INT)-1 AS CHAR(4))
                AND CAST(CAST(LEFT(c.latest_use_apr,4) AS INT)+1 AS CHAR(4))),
       c2 = (SELECT TOP 1 c.complex_id FROM gold.complex c
              WHERE c.sigungu_cd=a.sigungu_cd AND c.bjdong_cd=a.bjdong_cd
                AND c.hhld_cnt_sum = a.hhld_cnt
                AND a.use_apr_day IS NOT NULL
                AND LEFT(a.use_apr_day,4) BETWEEN
                    CAST(CAST(LEFT(c.oldest_use_apr,4) AS INT)-1 AS CHAR(4))
                AND CAST(CAST(LEFT(c.latest_use_apr,4) AS INT)+1 AS CHAR(4)))
  INTO #p
  FROM silver.arch_permit a
 WHERE a.is_current = 1 AND a.hhld_cnt >= 30;
GO
PRINT '--- 0. 대상 (세대수 30 이상인 허가) ---';
SELECT 허가수 = COUNT(*), PNU로붙음 = SUM(CASE WHEN pnu_cid IS NOT NULL THEN 1 ELSE 0 END)
  FROM #p;
GO

PRINT '--- 1. (법정동+세대수) 만으로 ---';
SELECT 후보단지수 = CASE WHEN n1 = 0 THEN N'0 (없음)'
                         WHEN n1 = 1 THEN N'1 (유일)' ELSE N'2+ (모호)' END,
       허가수 = COUNT(*)
  FROM #p
 GROUP BY CASE WHEN n1 = 0 THEN N'0 (없음)'
               WHEN n1 = 1 THEN N'1 (유일)' ELSE N'2+ (모호)' END
 ORDER BY 1;
GO

PRINT '--- 2. + 사용승인 연도 (단지 범위 +-1년) ---';
SELECT 후보단지수 = CASE WHEN n2 = 0 THEN N'0 (없음)'
                         WHEN n2 = 1 THEN N'1 (유일)' ELSE N'2+ (모호)' END,
       허가수 = COUNT(*)
  FROM #p
 GROUP BY CASE WHEN n2 = 0 THEN N'0 (없음)'
               WHEN n2 = 1 THEN N'1 (유일)' ELSE N'2+ (모호)' END
 ORDER BY 1;
GO

PRINT '--- 3. ★ 진짜 검증 : PNU 와 다리가 둘 다 될 때 같은 답인가 ---';
SELECT 판정 = CASE WHEN pnu_cid IS NULL THEN N'PNU 로는 안 붙음'
                   WHEN n1 <> 1        THEN N'다리가 유일하지 않음'
                   WHEN pnu_cid = c1   THEN N'★ 일치'
                   ELSE N'⚠ 어긋남' END,
       허가수 = COUNT(*)
  FROM #p
 GROUP BY CASE WHEN pnu_cid IS NULL THEN N'PNU 로는 안 붙음'
               WHEN n1 <> 1        THEN N'다리가 유일하지 않음'
               WHEN pnu_cid = c1   THEN N'★ 일치'
               ELSE N'⚠ 어긋남' END
 ORDER BY 허가수 DESC;
GO

PRINT '--- 4. 어긋난 것이 있으면 그 자리 (최대 15건) ---';
SELECT TOP 15 p.mgm_pmsrgst_pk, 허가명 = p.bld_nm, p.hhld_cnt, p.use_apr_day,
       PNU단지 = (SELECT complex_nm FROM gold.complex c WHERE c.complex_id = p.pnu_cid),
       다리단지 = (SELECT complex_nm FROM gold.complex c WHERE c.complex_id = p.c1)
  FROM #p p
 WHERE p.pnu_cid IS NOT NULL AND p.n1 = 1 AND p.pnu_cid <> p.c1;
GO

PRINT '--- 5. ★ 다리가 새로 여는 것 : PNU 로는 안 붙는데 다리로는 유일하게 붙음 ---';
SELECT 건수 = COUNT(*) FROM #p WHERE pnu_cid IS NULL AND n1 = 1;
SELECT TOP 20 p.mgm_pmsrgst_pk, 허가명 = p.bld_nm, p.hhld_cnt, p.arch_gb_nm, p.use_apr_day,
       새로붙는단지 = (SELECT complex_nm FROM gold.complex c WHERE c.complex_id = p.c1)
  FROM #p p WHERE p.pnu_cid IS NULL AND p.n1 = 1
 ORDER BY p.hhld_cnt DESC;
GO
