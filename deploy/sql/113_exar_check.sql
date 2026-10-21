/* ============================================================
   113_exar_check : 전유공용면적 적재 검증 (읽기 전용)  2026-10-18

   묻는 것 넷:
     1. 받은 건수가 다 들어왔나 — collapse 가 페이지 경계에서 덮어썼는지
        **SUM(seg_cnt) vs API items** 로 잰다. 적재기 말을 믿지 않고 밖에서 센다.
     2. 전유/공용 비율 — 기각 사유("80%가 공용")가 실제로 그런가
     3. 테스트단지 49101·103835 에 전용면적이 붙나
     4. 호 단위로 이을 수 있나 — expos(호) 와 키가 맞는가
   ============================================================ */
USE Teomoony;
GO
SET NOCOUNT ON;
GO

PRINT '--- 1. 행수 vs seg_cnt 합 (API items: 장위 70,242 / 수색 58,655) ---';
SELECT 법정동 = CASE WHEN sigungu_cd='11290' THEN N'장위동' ELSE N'수색동' END,
       행수 = COUNT(*), seg합 = SUM(ISNULL(seg_cnt,1)),
       seg_null = SUM(CASE WHEN seg_cnt IS NULL THEN 1 ELSE 0 END)
  FROM silver.bld_expos_pubuse_area
 WHERE is_current=1 AND (sigungu_cd='11290' OR sigungu_cd='11380')
 GROUP BY sigungu_cd;
PRINT '  seg합 이 items 와 같으면 손실 0. 작으면 페이지 경계에서 덮어쓴 것이다.';
GO

PRINT '--- 2. 전유 / 공용 비율 ---';
SELECT 구분 = CASE expos_pubuse_gb_cd WHEN '1' THEN N'전유' WHEN '2' THEN N'공용'
                 ELSE ISNULL(expos_pubuse_gb_cd,N'(없음)') END,
       행수 = COUNT(*), 면적합 = CAST(SUM(area) AS DECIMAL(18,1))
  FROM silver.bld_expos_pubuse_area WHERE is_current=1
 GROUP BY expos_pubuse_gb_cd ORDER BY 1;
GO

PRINT '--- 3. 테스트단지에 전용면적이 붙나 ---';
SELECT c.complex_id, c.complex_nm,
       호_전유 = COUNT(DISTINCT a.mgm_bldrgst_pk),
       전유행 = COUNT(*),
       면적_최소 = MIN(a.area), 면적_최대 = MAX(a.area)
  FROM gold.complex c
  JOIN gold.complex_pnu cp ON cp.complex_id = c.complex_id
  JOIN silver.bld_expos_pubuse_area a
    ON a.pnu = cp.pnu AND a.is_current=1 AND a.expos_pubuse_gb_cd='1'
 WHERE c.complex_id IN (49101, 103835)
 GROUP BY c.complex_id, c.complex_nm;
PRINT '  49101 래미안 장위(1,562세대) / 103835 DMC 롯데캐슬(1,192세대)';
GO

PRINT '--- 4. 호(expos) 와 키가 맞나 — 전유 행이 호에 1:1 로 붙나 ---';
SELECT 단지 = c.complex_id,
       호수 = COUNT(DISTINCT e.mgm_bldrgst_pk),
       면적붙은호 = COUNT(DISTINCT a.mgm_bldrgst_pk)
  FROM gold.complex c
  JOIN gold.complex_pnu cp ON cp.complex_id = c.complex_id
  JOIN silver.bld_expos e ON e.pnu = cp.pnu AND e.is_current=1
  LEFT JOIN silver.bld_expos_pubuse_area a
    ON a.mgm_bldrgst_pk = e.mgm_bldrgst_pk AND a.is_current=1 AND a.expos_pubuse_gb_cd='1'
 WHERE c.complex_id IN (49101, 103835)
 GROUP BY c.complex_id;
PRINT '  두 숫자가 같으면 호 단위로 전용면적을 띄울 수 있다.';
GO

PRINT '--- 5. 평형 분포 (49101) — 실거래 평형과 맞춰볼 수 있나 ---';
SELECT TOP 12 평형 = CAST(FLOOR(a.area) AS INT), 호수 = COUNT(*)
  FROM gold.complex_pnu cp
  JOIN silver.bld_expos_pubuse_area a
    ON a.pnu = cp.pnu AND a.is_current=1 AND a.expos_pubuse_gb_cd='1'
 WHERE cp.complex_id = 49101
 GROUP BY CAST(FLOOR(a.area) AS INT) ORDER BY COUNT(*) DESC;
GO
