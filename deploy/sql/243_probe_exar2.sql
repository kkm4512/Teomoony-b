/* 전용률 집계가 왜 느린가. 같은 단지(524566 리센츠, 5,564호)로 네 변형을 잰다.
   ★ 재고 나서 고른다 — 짐작으로 두 번 헛짚은 자리다(_q_hos 1.9초 상수). */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* B 기준선: _q_hos 가 지금 하는 것과 같은 모양 (전유만) */
SELECT 변형 = 'B 전유만 APPLY', 잰호 = COUNT(*), 전유합 = SUM(x.전유)
  FROM gold.v_complex_ho h
 CROSS APPLY (SELECT 전유 = SUM(a.area)
                FROM silver.bld_expos_pubuse_area a
               WHERE a.mgm_bldrgst_pk = h.호PK AND a.is_current = 1
                 AND a.expos_pubuse_gb_cd = '1') x
 WHERE h.complex_id = 524566 AND x.전유 > 0;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* A 지금 넣은 것: 구분 거름 없이 CASE 로 둘 다 */
SELECT 변형 = 'A CASE 둘다 APPLY', 잰호 = COUNT(*), 전유합 = SUM(x.전유), 공용합 = SUM(x.공용)
  FROM gold.v_complex_ho h
 CROSS APPLY (SELECT 전유 = SUM(CASE WHEN a.expos_pubuse_gb_cd = '1' THEN a.area END),
                     공용 = SUM(CASE WHEN a.expos_pubuse_gb_cd = '2' THEN a.area END)
                FROM silver.bld_expos_pubuse_area a
               WHERE a.mgm_bldrgst_pk = h.호PK AND a.is_current = 1) x
 WHERE h.complex_id = 524566 AND x.전유 > 0 AND x.공용 > 0;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* C 조인 + 호 단위로 한 번 뭉친 뒤 올린다 (APPLY 없음) */
WITH 호별 AS (
  SELECT h.호PK,
         전유 = SUM(CASE WHEN a.expos_pubuse_gb_cd = '1' THEN a.area END),
         공용 = SUM(CASE WHEN a.expos_pubuse_gb_cd = '2' THEN a.area END)
    FROM gold.v_complex_ho h
    JOIN silver.bld_expos_pubuse_area a
      ON a.mgm_bldrgst_pk = h.호PK AND a.is_current = 1
   WHERE h.complex_id = 524566
   GROUP BY h.호PK
)
SELECT 변형 = 'C 조인+CTE', 잰호 = COUNT(*), 전유합 = SUM(전유), 공용합 = SUM(공용)
  FROM 호별 WHERE 전유 > 0 AND 공용 > 0;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* D A 와 같되 바깥 거름(전유>0 AND 공용>0)을 뺀다 — 거름이 범인인지 가른다 */
SELECT 변형 = 'D CASE 둘다, 거름없음', 잰호 = COUNT(*), 전유합 = SUM(x.전유), 공용합 = SUM(x.공용)
  FROM gold.v_complex_ho h
 CROSS APPLY (SELECT 전유 = SUM(CASE WHEN a.expos_pubuse_gb_cd = '1' THEN a.area END),
                     공용 = SUM(CASE WHEN a.expos_pubuse_gb_cd = '2' THEN a.area END)
                FROM silver.bld_expos_pubuse_area a
               WHERE a.mgm_bldrgst_pk = h.호PK AND a.is_current = 1) x
 WHERE h.complex_id = 524566;
