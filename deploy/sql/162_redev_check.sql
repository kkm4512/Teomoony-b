/* 162. 정비구역이 단지에 붙나 (2026-10-19) — 읽기 전용
   ★ v_complex_redev 는 complex_id 로 **반드시** 걸러 쓴다(11-41 교훈).
     여기서도 단지를 먼저 좁힌 뒤 교차시킨다. */
SET NOCOUNT ON;
PRINT '--- A. 적재 현황 ---';
SELECT 구역 = COUNT(*), 시군구 = COUNT(DISTINCT signgu_se),
       geom = SUM(CASE WHEN geom IS NOT NULL THEN 1 ELSE 0 END),
       코드없음 = SUM(CASE WHEN biz_nm IS NULL THEN 1 ELSE 0 END)
  FROM silver.redev_zone WHERE is_current = 1;

PRINT '';
PRINT '--- B. 코드표에 없던 것들이 무엇인가 ---';
SELECT sclas_cl, lclas_cl, propel_cd, 건수 = COUNT(*),
       예시 = MIN(LEFT(zone_nm, 34))
  FROM silver.redev_zone
 WHERE is_current = 1 AND (biz_nm IS NULL OR propel_nm IS NULL)
 GROUP BY sclas_cl, lclas_cl, propel_cd;

PRINT '';
PRINT '--- C. 장위 단지들이 어느 구역에 들어가나 ---';
SELECT 단지 = LEFT(c.complex_nm, 22), 세대 = c.hhld_cnt_sum,
       구역 = LEFT(v.zone_nm, 20), 사업 = v.biz_nm, 단계 = v.propel_nm,
       단지가구역안 = CAST(100.0 * SUM(v.xarea) / NULLIF(SUM(v.parea), 0) AS DECIMAL(5,1))
  FROM gold.complex c
  JOIN gold.v_complex_redev v ON v.complex_id = c.complex_id
 WHERE c.is_active = 1 AND c.has_recap = 1 AND c.hhld_cnt_sum >= 300
   AND c.rep_plat_plc LIKE N'%장위동%'
 GROUP BY c.complex_nm, c.hhld_cnt_sum, v.zone_nm, v.biz_nm, v.propel_nm
 ORDER BY c.hhld_cnt_sum DESC;

PRINT '';
PRINT '--- D. 성북구 300세대+ 단지 중 정비구역에 걸친 비율 ---';
WITH c AS (
  SELECT c.complex_id,
         hit = CASE WHEN EXISTS (SELECT 1 FROM gold.v_complex_redev v
                                  WHERE v.complex_id = c.complex_id) THEN 1 ELSE 0 END
    FROM gold.complex c
   WHERE c.is_active = 1 AND c.has_recap = 1 AND c.sigungu_cd = '11290'
     AND c.hhld_cnt_sum >= 300
)
SELECT 단지 = COUNT(*), 정비구역있음 = SUM(hit) FROM c;
