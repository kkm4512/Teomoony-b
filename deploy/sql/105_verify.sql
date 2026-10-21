/* ============================================================
   105_verify : hsprc 완결 뒤 남은 숙제를 확인한다 (진단용 · 읽기 전용)
                2026-10-18, 은평 주택가격 3개 법정동을 닫은 직후.

   묻는 것 넷:
     1. 은평 hsprc 가 정말 다 찼나 (적재기 말이 아니라 DB 에 묻는다)
     2. 103835 DMC 롯데캐슬 - 공시가격이 붙었나, 층 프리미엄이 보이나
     3. 57232 브라운스톤 돈암 - 전유부가 14,666 으로 다 찼나 (지금 8,702)
     4. 돈암동이 meta.load_target 에 있나  <- 없으면 영영 안 받아온다
   ============================================================ */
USE Teomoony;
GO
SET NOCOUNT ON;
GO

PRINT '--- 1. 은평(11380) 축별 행 수 ---';
SELECT ax='hsprc', bjdong_cd, n=COUNT(*)
  FROM silver.bld_hsprc  WHERE is_current=1 AND sigungu_cd='11380' GROUP BY bjdong_cd
UNION ALL SELECT 'expos', bjdong_cd, COUNT(*)
  FROM silver.bld_expos  WHERE is_current=1 AND sigungu_cd='11380' GROUP BY bjdong_cd
ORDER BY ax, bjdong_cd;
GO

PRINT '--- 2. 103835 DMC 롯데캐슬 더 퍼스트 ---';
SELECT c.complex_id, c.complex_nm, c.sigungu_cd, c.bjdong_cd,
       c.dong_cnt, c.hhld_cnt_sum, c.rep_pnu
  FROM gold.complex c WHERE c.complex_id = 103835;

PRINT '  2-1. 이 단지 대장에 붙은 공시가격 건수';
SELECT 공시행수 = COUNT(*), 호수 = COUNT(DISTINCT h.mgm_bldrgst_pk),
       회차 = COUNT(DISTINCT h.std_day), 최신 = MAX(h.std_day)
  FROM gold.complex_bld cb
  JOIN silver.bld_hsprc h ON h.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND h.is_current=1
 WHERE cb.complex_id = 103835;

PRINT '  2-2. 층 프리미엄이 보이나 - 최신 회차, 층별 평균 (전유부가 있어야 층이 나온다)';
WITH latest AS (SELECT MAX(std_day) d FROM silver.bld_hsprc h
                  JOIN gold.complex_bld cb ON cb.mgm_bldrgst_pk=h.mgm_bldrgst_pk
                 WHERE cb.complex_id=103835 AND h.is_current=1)
SELECT TOP 20 e.flr_no, 호수=COUNT(*), 평균공시=AVG(h.hsprc), 최저=MIN(h.hsprc), 최고=MAX(h.hsprc)
  FROM gold.complex_bld cb
  JOIN silver.bld_hsprc h ON h.mgm_bldrgst_pk=cb.mgm_bldrgst_pk AND h.is_current=1
  JOIN silver.bld_expos e ON e.mgm_bldrgst_pk=h.mgm_bldrgst_pk AND e.is_current=1
 WHERE cb.complex_id=103835 AND h.std_day=(SELECT d FROM latest)
 GROUP BY e.flr_no ORDER BY e.flr_no;
GO

PRINT '--- 3. 57232 브라운스톤 돈암 - 전유부 ---';
SELECT c.complex_id, c.complex_nm, c.dong_cnt, c.hhld_cnt_sum FROM gold.complex c WHERE c.complex_id=57232;
SELECT 전유부행수 = COUNT(*), 동 = COUNT(DISTINCT e.dong_nm), 호 = COUNT(DISTINCT e.ho_nm)
  FROM gold.complex_bld cb
  JOIN silver.bld_expos e ON e.mgm_bldrgst_pk=cb.mgm_bldrgst_pk AND e.is_current=1
 WHERE cb.complex_id=57232;
PRINT '  (14,666 이면 다 찬 것. 8,702 면 10-17 상태 그대로다)';
GO

PRINT '--- 4. meta.load_target - 돈암동(11290/10700)이 등록돼 있나 ---';
SELECT sgg_cd, bjdong_cd, ops=ISNULL(ops,'(전체)'), enabled, note
  FROM meta.load_target ORDER BY sgg_cd, bjdong_cd;
PRINT '  11290 에 10700(돈암동) 행이 없으면 run_plan 이 영영 안 집는다.';
GO

PRINT '--- 5. 남은 일 (법정동 x op) ---';
SELECT sgg_cd, op_alias, 법정동수=COUNT(*),
       완료=SUM(CASE WHEN status='DONE' THEN 1 ELSE 0 END),
       재시도=SUM(CASE WHEN status='RETRY' THEN 1 ELSE 0 END),
       남음=SUM(CASE WHEN status='TODO' THEN 1 ELSE 0 END)
  FROM meta.v_load_plan GROUP BY sgg_cd, op_alias
 HAVING SUM(CASE WHEN status IN ('TODO','RETRY') THEN 1 ELSE 0 END) > 0
 ORDER BY sgg_cd, op_alias;
PRINT '  행이 없으면 대장/인허가 쪽은 전부 끝난 것이다.';
GO
