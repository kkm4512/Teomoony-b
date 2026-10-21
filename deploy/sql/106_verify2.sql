/* ============================================================
   106_verify2 : 105 의 조인을 고쳐 다시 묻는다 (진단용 · 읽기 전용)

   ★ 105 가 왜 0 건을 냈나
     `gold.complex_bld` 로 조인했다. 그런데 hsprc·expos 의 mgm_bldrgst_pk 는
     **전유부(호 단위) PK** 이고(26_expos.sql 19행), complex_bld 는 전유부를
     **빼고** 만든다(README 5장 - 호 단위라 단지 묶기에서 제외).
     그래서 0 건은 데이터가 없어서가 아니라 **조인이 만든 거짓말**이었다.
     -> PNU 로 잇는다. 제1원칙 그대로다.

   덤: 진관동 hsprc 가 DB 287,159 인데 API totalCount 는 287,160 이다.
       1 행 차이의 정체를 같이 본다.
   ============================================================ */
USE Teomoony;
GO
SET NOCOUNT ON;
GO

PRINT '--- 1. 103835 DMC 롯데캐슬 - PNU 로 이은 공시가격 ---';
SELECT 공시행수=COUNT(*), 호수=COUNT(DISTINCT h.mgm_bldrgst_pk),
       회차=COUNT(DISTINCT h.std_day), 최신회차=MAX(h.std_day)
  FROM gold.complex_pnu cp
  JOIN silver.bld_hsprc h ON h.pnu = cp.pnu AND h.is_current = 1
 WHERE cp.complex_id = 103835;

PRINT '  1-1. 층 프리미엄 (최신 회차 · 층별 평균)';
WITH latest AS (
    SELECT MAX(h.std_day) d
      FROM gold.complex_pnu cp
      JOIN silver.bld_hsprc h ON h.pnu=cp.pnu AND h.is_current=1
     WHERE cp.complex_id=103835)
SELECT TOP 30 e.flr_no, 호수=COUNT(*), 평균공시=AVG(h.hsprc),
       최저=MIN(h.hsprc), 최고=MAX(h.hsprc)
  FROM gold.complex_pnu cp
  JOIN silver.bld_hsprc h ON h.pnu=cp.pnu AND h.is_current=1
  JOIN silver.bld_expos e ON e.mgm_bldrgst_pk=h.mgm_bldrgst_pk AND e.is_current=1
 WHERE cp.complex_id=103835 AND h.std_day=(SELECT d FROM latest)
 GROUP BY e.flr_no ORDER BY e.flr_no;
GO

PRINT '--- 2. 57232 브라운스톤 돈암 - PNU 로 이은 전유부/공시 ---';
SELECT 전유부행수=COUNT(*), 동=COUNT(DISTINCT e.dong_nm), 호=COUNT(DISTINCT e.ho_nm)
  FROM gold.complex_pnu cp
  JOIN silver.bld_expos e ON e.pnu = cp.pnu AND e.is_current = 1
 WHERE cp.complex_id = 57232;
PRINT '  (세대 1,074 · 24동. 14,666 이면 다 찬 것, 8,702 면 10-17 그대로)';
SELECT 공시행수=COUNT(*), 회차=COUNT(DISTINCT h.std_day)
  FROM gold.complex_pnu cp
  JOIN silver.bld_hsprc h ON h.pnu = cp.pnu AND h.is_current = 1
 WHERE cp.complex_id = 57232;
GO

PRINT '--- 3. 진관동 hsprc 1행 차이의 정체 ---';
SELECT 행수=COUNT(*),
       자연키_유일=COUNT(DISTINCT CONCAT(mgm_bldrgst_pk,'|',std_day,'|',ISNULL(crtn_day,'')))
  FROM silver.bld_hsprc WHERE is_current=1 AND sigungu_cd='11380' AND bjdong_cd='11400';
PRINT '  둘이 같으면 API 가 같은 자연키를 두 번 준 것(중복 1건). 다르면 이력이 겹친 것.';
GO

PRINT '--- 4. meta.v_load_plan 이 실제로 가진 컬럼 (105 에서 status 가 없었다) ---';
SELECT COLUMN_NAME, DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS
 WHERE TABLE_SCHEMA='meta' AND TABLE_NAME='v_load_plan' ORDER BY ORDINAL_POSITION;
GO
