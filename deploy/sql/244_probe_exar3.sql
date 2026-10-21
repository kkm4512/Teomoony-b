/* _q_exar 의 **최종 모양** 그대로. 243 에서 잰 값과 맞아야 한다 —
   524566: 잰호 5,563 / 전유 447,329.99 / 공용 439,937.28
   ★ 모양을 바꿨으면 숫자가 그대로인지 다시 맞춰 본다. 빨라도 다르면 못 쓴다. */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 단지 = h.complex_id,
       잰호        = SUM(CASE WHEN x.전유 > 0 AND x.공용 > 0 THEN 1 ELSE 0 END),
       면적행있는호 = COUNT(*),
       전유합      = SUM(CASE WHEN x.전유 > 0 AND x.공용 > 0 THEN x.전유 END),
       공용합      = SUM(CASE WHEN x.전유 > 0 AND x.공용 > 0 THEN x.공용 END)
  FROM gold.v_complex_ho h
 CROSS APPLY (
   SELECT 전유 = SUM(CASE WHEN a.expos_pubuse_gb_cd = '1' THEN a.area END),
          공용 = SUM(CASE WHEN a.expos_pubuse_gb_cd = '2' THEN a.area END)
     FROM silver.bld_expos_pubuse_area a
    WHERE a.mgm_bldrgst_pk = h.호PK
      AND a.is_current = 1) x
 WHERE h.complex_id IN (524566, 528197, 545277)
   AND (x.전유 > 0 OR x.공용 > 0)
 GROUP BY h.complex_id
 ORDER BY h.complex_id;
