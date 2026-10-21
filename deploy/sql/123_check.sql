/* ============================================================
   123_check : (1) 은평 전유공용면적 적재 검증  (2) 합필 가설 확인  2026-10-18
   읽기 전용.
   ============================================================ */
USE Teomoony;
GO
SET NOCOUNT ON;
GO

PRINT '=== A. 은평 전유공용면적 적재 결과 ===';
PRINT '--- A1. 법정동별 행수 / 호수 / 전유 1:1 ---';
SELECT a.sigungu_cd, a.bjdong_cd,
       행수   = COUNT(*),
       구획합 = SUM(ISNULL(a.seg_cnt,1)),
       전유행 = SUM(CASE WHEN a.expos_pubuse_gb_cd='1' THEN 1 ELSE 0 END),
       공용행 = SUM(CASE WHEN a.expos_pubuse_gb_cd='2' THEN 1 ELSE 0 END),
       호수   = COUNT(DISTINCT a.mgm_bldrgst_pk)
  FROM silver.bld_expos_pubuse_area a
 WHERE a.is_current = 1
 GROUP BY a.sigungu_cd, a.bjdong_cd
 ORDER BY a.sigungu_cd, a.bjdong_cd;
PRINT '  전유행 = 호수 여야 한다(호당 전유 1행). 어긋나면 자연키가 의심이다.';
GO

PRINT '--- A2. 전유가 1:1 이 아닌 호 (있으면 버그) ---';
SELECT TOP 10 a.mgm_bldrgst_pk, 전유행수 = COUNT(*)
  FROM silver.bld_expos_pubuse_area a
 WHERE a.is_current = 1 AND a.expos_pubuse_gb_cd = '1'
 GROUP BY a.mgm_bldrgst_pk HAVING COUNT(*) > 1;
GO

PRINT '--- A3. 전유부(호) 대비 면적이 붙은 비율 ---';
SELECT e.sigungu_cd, e.bjdong_cd,
       호수 = COUNT(*),
       면적있음 = SUM(CASE WHEN x.mgm_bldrgst_pk IS NOT NULL THEN 1 ELSE 0 END),
       비율 = CAST(100.0 * SUM(CASE WHEN x.mgm_bldrgst_pk IS NOT NULL THEN 1 ELSE 0 END)
                   / NULLIF(COUNT(*),0) AS DECIMAL(5,1))
  FROM silver.bld_expos e
  LEFT JOIN (SELECT DISTINCT mgm_bldrgst_pk FROM silver.bld_expos_pubuse_area
              WHERE is_current=1 AND expos_pubuse_gb_cd='1') x
         ON x.mgm_bldrgst_pk = e.mgm_bldrgst_pk
 WHERE e.is_current = 1 AND e.sigungu_cd = '11380'
 GROUP BY e.sigungu_cd, e.bjdong_cd ORDER BY e.bjdong_cd;
GO

PRINT '=== B. 합필 가설 확인 ===';
PRINT '--- B1. 길음역 롯데캐슬 트윈골드 : 청약홈 542-1 vs 우리 PNU ---';
/* 청약홈은 길음동(1129013400) 542-1 이라 했는데 그 PNU 가 없다.
   같은 법정동에서 이름이 비슷한 신축/단지의 PNU 를 보면 본번이 어떻게
   달라졌는지 보인다. ★ 이름 매칭은 이 진단에만 쓴다(정책 1장). */
SELECT 출처 = N'신축(K-apt)', n.kapt_name, n.pnu, 세대 = n.hhld_cnt
  FROM gold.v_newbuild n
 WHERE n.pnu LIKE '1129013400%' OR n.kapt_name LIKE N'%트윈골드%'
UNION ALL
SELECT N'대장단지', c.complex_nm, cp.pnu, c.hhld_cnt_sum
  FROM gold.complex c JOIN gold.complex_pnu cp ON cp.complex_id = c.complex_id
 WHERE cp.pnu LIKE '1129013400%' AND c.hhld_cnt_sum >= 300;
GO

PRINT '--- B2. 장위동 : 청약홈 62-1 / 25-55 / 68-37 주변 PNU ---';
SELECT TOP 30 출처 = N'대장단지', c.complex_nm, cp.pnu, c.hhld_cnt_sum
  FROM gold.complex c JOIN gold.complex_pnu cp ON cp.complex_id = c.complex_id
 WHERE cp.pnu LIKE '1129013800%' AND c.hhld_cnt_sum >= 300
 ORDER BY cp.pnu;
GO

PRINT '--- B3. 안암동은 왜 법정동명으로 안 풀렸나 ---';
SELECT lawd_cd, sgg_nm, emd_nm, ri_nm, is_abolished
  FROM meta.lawd_code
 WHERE sgg_nm = N'성북구' AND emd_nm LIKE N'안암동%'
 ORDER BY lawd_cd;
GO
