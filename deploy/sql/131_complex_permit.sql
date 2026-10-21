/* ============================================================
   131_complex_permit : 허가 <-> 단지 연결을 **근거와 함께** 만든다  2026-10-18

   ★ 왜 뷰를 따로 두나
     지금까지 화면은 `arch_permit.pnu = complex_pnu.pnu` 정확일치로만 붙였다.
     그래서 재개발 단지는 허가가 **0건**으로 보였다 — 합필 때 본번이 새로
     바뀌는데 인허가에는 옛 지번만 있기 때문이다(CONTEXT 11-22).
     다리를 찾았으니(11-23) 붙이되, **어떻게 붙었는지를 같이 들고 다닌다.**

   ★ match_by 를 반드시 남긴다
     PNU 로 붙은 것과 세대수로 붙은 것은 **신뢰도가 다르다.** 조용히 섞으면
     나중에 "이건 왜 붙었나" 를 되짚을 수 없다. 화면도 이 값을 보고 적는다.

   ★ HHLD 다리의 조건 (11-23 에서 전수 측정으로 정했다. 임의로 고르지 않았다)
       신축 + 150세대 이상 + (법정동,세대수) 후보가 **유일**
     이 셋을 다 만족할 때 38건 중 PNU 와 **어긋남 0**, 새로 열림 8.
     조건을 하나라도 풀면 어긋나기 시작한다:
       - 150세대 미만    -> 작은 세대수는 한 법정동에 여럿이라 우연히 걸린다
       - 용도변경·대수선 -> 어긋난 14건이 전부 이것이었다(대일빌딩·피카디리플러스)
     그리고 **PNU 로 붙는 허가에는 아예 적용하지 않는다.** PNU 가 먼저다.
   ============================================================ */
USE Teomoony;
GO

IF OBJECT_ID('gold.v_complex_permit') IS NOT NULL DROP VIEW gold.v_complex_permit;
GO
CREATE VIEW gold.v_complex_permit
AS
/* 1순위 — PNU 정확일치. 한 단지에 PNU 가 여럿이라 DISTINCT 가 필요하다. */
SELECT DISTINCT
       complex_id      = cp.complex_id,
       mgm_pmsrgst_pk  = a.mgm_pmsrgst_pk,
       match_by        = CONVERT(VARCHAR(8), 'PNU')
  FROM gold.complex_pnu cp
  JOIN silver.arch_permit a
    ON a.pnu = cp.pnu AND a.is_current = 1

UNION ALL

/* 2순위 — 합필 다리. 위에서 못 붙은 것만. */
SELECT DISTINCT
       c.complex_id,
       a.mgm_pmsrgst_pk,
       CONVERT(VARCHAR(8), 'HHLD')
  FROM silver.arch_permit a
  JOIN gold.complex c
    ON c.sigungu_cd = a.sigungu_cd
   AND c.bjdong_cd  = a.bjdong_cd
   AND c.hhld_cnt_sum = a.hhld_cnt
 WHERE a.is_current = 1
   AND a.arch_gb_nm = N'신축'
   AND a.hhld_cnt >= 150
   AND NOT EXISTS (SELECT 1 FROM gold.complex_pnu cp WHERE cp.pnu = a.pnu)
   /* 후보가 유일할 때만. 둘 이상이면 가르지 못한 것이고, 못 가른 것은 안 붙인다. */
   AND (SELECT COUNT(*) FROM gold.complex c2
         WHERE c2.sigungu_cd = a.sigungu_cd
           AND c2.bjdong_cd  = a.bjdong_cd
           AND c2.hhld_cnt_sum = a.hhld_cnt) = 1;
GO

PRINT '--- 1. 연결 건수 ---';
SELECT match_by, 연결수 = COUNT(*), 단지수 = COUNT(DISTINCT complex_id)
  FROM gold.v_complex_permit GROUP BY match_by;
GO

PRINT '--- 2. 한 허가가 단지 둘에 붙지는 않나 (붙으면 버그) ---';
SELECT TOP 10 mgm_pmsrgst_pk, 단지수 = COUNT(DISTINCT complex_id)
  FROM gold.v_complex_permit
 GROUP BY mgm_pmsrgst_pk HAVING COUNT(DISTINCT complex_id) > 1;
GO

PRINT '--- 3. HHLD 로 새로 붙은 단지 ---';
SELECT c.complex_id, c.complex_nm, c.hhld_cnt_sum,
       허가수 = COUNT(*),
       허가명 = MAX(a.bld_nm)
  FROM gold.v_complex_permit v
  JOIN gold.complex c ON c.complex_id = v.complex_id
  JOIN silver.arch_permit a ON a.mgm_pmsrgst_pk = v.mgm_pmsrgst_pk AND a.is_current=1
 WHERE v.match_by = 'HHLD'
 GROUP BY c.complex_id, c.complex_nm, c.hhld_cnt_sum
 ORDER BY c.hhld_cnt_sum DESC;
GO

PRINT '--- 4. 허가가 붙은 단지 수 : 전 / 후 ---';
SELECT 전_PNU만 = (SELECT COUNT(DISTINCT complex_id) FROM gold.v_complex_permit WHERE match_by='PNU'),
       후_전체  = (SELECT COUNT(DISTINCT complex_id) FROM gold.v_complex_permit);
GO
