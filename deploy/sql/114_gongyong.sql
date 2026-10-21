/* ============================================================
   114_gongyong : 공용면적이 왜 큰가 (읽기 전용)  2026-10-18

   화면에 전용률 45.3% 가 떴다. 아파트 통념(70~80%)과 안 맞는다.
   가설이 둘이고 **아직 어느 쪽인지 모른다**:
     (1) 집계가 틀렸다 — 자연키가 넓어 서로 다른 공용 항목이 뭉쳤거나
         collapse 가 페이지 경계에서 덮었다
     (2) 집계는 맞고 **내가 이름을 잘못 붙였다** — 전유공용면적의 '공용' 은
         주거공용 + **기타공용(주차장 등)** 을 다 담는다. 그러면
         전유/(전유+전체공용) 은 '전용률' 이 아니라 **계약면적 기준**이고
         45~55% 가 정상이다.
   행을 직접 본다. 숫자를 보기 전에 결론을 적지 않는다.
   ============================================================ */
USE Teomoony;
GO
SET NOCOUNT ON;
GO

PRINT '--- 1. 한 호의 전유공용 행 전부 (래미안 장위 501동 2501호) ---';
SELECT a.expos_pubuse_gb_cd AS 구분, a.main_purps_nm AS 용도, a.etc_purps AS 기타용도,
       a.flr_gb_cd AS 층구분, a.flr_no AS 층, a.strct_nm AS 구조,
       a.area AS 면적, a.seg_cnt AS 구획
  FROM silver.bld_expos e
  JOIN silver.bld_expos_pubuse_area a
    ON a.mgm_bldrgst_pk = e.mgm_bldrgst_pk AND a.is_current = 1
 WHERE e.is_current = 1 AND e.sigungu_cd = '11290' AND e.bjdong_cd = '13800'
   AND e.dong_nm = N'501동' AND e.ho_nm = N'2501'
 ORDER BY a.expos_pubuse_gb_cd, a.area DESC;
GO

PRINT '--- 2. 공용 용도 분포 (장위+수색 전체). 주차장이 섞여 있는가 ---';
SELECT TOP 15 용도 = ISNULL(main_purps_nm, N'(없음)'),
       행수 = COUNT(*), 면적합 = CAST(SUM(area) AS DECIMAL(18,1))
  FROM silver.bld_expos_pubuse_area
 WHERE is_current = 1 AND expos_pubuse_gb_cd = '2'
 GROUP BY main_purps_nm ORDER BY SUM(area) DESC;
GO

PRINT '--- 3. 호별 전용/공용 비율 분포 (49101) ---';
WITH h AS (
  SELECT a.mgm_bldrgst_pk,
         전유 = SUM(CASE WHEN a.expos_pubuse_gb_cd='1' THEN a.area END),
         공용 = SUM(CASE WHEN a.expos_pubuse_gb_cd='2' THEN a.area END)
    FROM gold.complex_pnu cp
    JOIN silver.bld_expos_pubuse_area a ON a.pnu = cp.pnu AND a.is_current=1
   WHERE cp.complex_id = 49101
   GROUP BY a.mgm_bldrgst_pk)
SELECT 구간 = CASE WHEN 전유/(전유+공용) < 0.4 THEN N'~40%'
                   WHEN 전유/(전유+공용) < 0.5 THEN N'40~50%'
                   WHEN 전유/(전유+공용) < 0.6 THEN N'50~60%'
                   WHEN 전유/(전유+공용) < 0.7 THEN N'60~70%'
                   ELSE N'70%~' END,
       호수 = COUNT(*)
  FROM h WHERE 전유 > 0 AND 공용 > 0
 GROUP BY CASE WHEN 전유/(전유+공용) < 0.4 THEN N'~40%'
               WHEN 전유/(전유+공용) < 0.5 THEN N'40~50%'
               WHEN 전유/(전유+공용) < 0.6 THEN N'50~60%'
               WHEN 전유/(전유+공용) < 0.7 THEN N'60~70%'
               ELSE N'70%~' END
 ORDER BY 1;
GO

PRINT '--- 4. collapse 가 뭉친 정도 — seg_cnt 분포 ---';
SELECT 구획수 = seg_cnt, 행수 = COUNT(*)
  FROM silver.bld_expos_pubuse_area WHERE is_current=1
 GROUP BY seg_cnt ORDER BY seg_cnt;
PRINT '  구획수가 2 이상인 행은 같은 자연키가 여러 번 온 것이다.';
GO
