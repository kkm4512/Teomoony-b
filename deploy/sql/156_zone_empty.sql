/* 156. uname 이 빈 구역이 얼마나 되나 (2026-10-18) — 읽기 전용 */
SET NOCOUNT ON;
SELECT 구분 = CASE WHEN uname IS NULL OR LTRIM(uname) = '' THEN N'빈값' ELSE N'이름있음' END,
       구역 = COUNT(*),
       면적합 = CAST(SUM(area_m2_approx)/1000000 AS DECIMAL(10,2))
  FROM silver.land_use_zone WHERE is_current = 1
 GROUP BY CASE WHEN uname IS NULL OR LTRIM(uname) = '' THEN N'빈값' ELSE N'이름있음' END;
PRINT '';
PRINT '--- 빈값 구역이 걸친 단지 수 ---';
SELECT 단지 = COUNT(DISTINCT v.complex_id)
  FROM gold.v_complex_zone v WHERE v.uname IS NULL OR LTRIM(v.uname) = '';
