/* 232_vlrat_dup : 한 단지의 동들이 같은 용적률을 들고 있나 (2026-10-20) 읽기만 한다.
   왜: 총괄표제부를 분위 바구니에 넣을지 정하려면, 표제부들이 **같은 대지의 같은 값**을
       여러 번 넣고 있는지 알아야 한다. 그렇다면 큰 단지가 바구니를 왜곡한다. */
USE Teomoony;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
PRINT '--- 동이 5개 이상인 단지에서, 표제부 용적률이 몇 가지나 되나 ---';
WITH b AS (
  SELECT cb.complex_id, t.vl_rat
    FROM gold.complex_bld cb
    JOIN silver.bld_title t ON t.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND t.is_current = 1
   WHERE t.vl_rat > 0
), g AS (
  SELECT complex_id, 동수 = COUNT(*), 값종류 = COUNT(DISTINCT vl_rat)
    FROM b GROUP BY complex_id
)
SELECT 단지수 = COUNT(*),
       한값만 = SUM(CASE WHEN 값종류 = 1 THEN 1 ELSE 0 END),
       여러값 = SUM(CASE WHEN 값종류 > 1 THEN 1 ELSE 0 END),
       동합계 = SUM(동수)
  FROM g WHERE 동수 >= 5;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
PRINT '--- 분위 바구니에 든 258,886 건 중, 같은 단지가 여러 번 든 것 ---';
WITH v AS (
  SELECT f.mgm_bldrgst_pk, cb.complex_id
    FROM gold.bld_vlrat f
    LEFT JOIN gold.complex_bld cb ON cb.mgm_bldrgst_pk = f.mgm_bldrgst_pk
   WHERE f.상위percent IS NOT NULL
)
SELECT 분위건수 = COUNT(*),
       단지에속함 = SUM(CASE WHEN complex_id IS NULL THEN 0 ELSE 1 END),
       단지수 = COUNT(DISTINCT complex_id);
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
PRINT '--- 보기: 동 많은 단지 셋 ---';
SELECT TOP 3 cb.complex_id, 동수 = COUNT(*), 값종류 = COUNT(DISTINCT t.vl_rat),
       최소 = MIN(t.vl_rat), 최대 = MAX(t.vl_rat)
  FROM gold.complex_bld cb
  JOIN silver.bld_title t ON t.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND t.is_current = 1
 WHERE t.vl_rat > 0
 GROUP BY cb.complex_id ORDER BY COUNT(*) DESC;
GO
