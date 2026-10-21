/* 168. 지역지구구역 probe 확인 + VWorld 용도지역과 교차검증 (2026-10-19) — 읽기 전용 */
SET NOCOUNT ON;
PRINT '--- A. 적재 ---';
SELECT 행 = COUNT(*), 건물PK = COUNT(DISTINCT mgm_bldrgst_pk), PNU = COUNT(DISTINCT pnu)
  FROM silver.bld_jijigu WHERE is_current = 1;
PRINT '';
PRINT '--- B. 구분별 ---';
SELECT 구분 = jijigu_gb_nm, 행 = COUNT(*), 종류 = COUNT(DISTINCT jijigu_nm)
  FROM silver.bld_jijigu WHERE is_current = 1
 GROUP BY jijigu_gb_nm ORDER BY COUNT(*) DESC;
PRINT '';
PRINT '--- C. 용도지역만 상위 ---';
SELECT TOP 8 jijigu_nm, 행 = COUNT(*)
  FROM silver.bld_jijigu WHERE is_current = 1 AND jijigu_gb_cd = '1'
 GROUP BY jijigu_nm ORDER BY COUNT(*) DESC;
PRINT '';
PRINT '--- D. ★ 교차검증: 대장(지역지구) vs VWorld(공간교차) ---';
WITH c AS (
  SELECT c.complex_id, c.complex_nm
    FROM gold.complex c
   WHERE c.is_active = 1 AND c.has_recap = 1 AND c.hhld_cnt_sum >= 300
     AND c.rep_plat_plc LIKE N'%장위동%'
), 대장 AS (
  SELECT c.complex_id, nm = MAX(j.jijigu_nm)
    FROM c JOIN gold.complex_bld cb ON cb.complex_id = c.complex_id
           JOIN silver.bld_jijigu j ON j.mgm_bldrgst_pk = cb.mgm_bldrgst_pk
                                   AND j.is_current = 1 AND j.jijigu_gb_cd = '1'
   GROUP BY c.complex_id
), 공간 AS (
  SELECT v.complex_id, nm = MAX(v.uname)
    FROM gold.v_complex_zone v
   WHERE v.complex_id IN (SELECT complex_id FROM c)
   GROUP BY v.complex_id
)
SELECT 단지 = LEFT(c.complex_nm, 24),
       대장 = ISNULL(d.nm, N'(없음)'), VWorld = ISNULL(s.nm, N'(없음)'),
       일치 = CASE WHEN d.nm = s.nm THEN N'O' WHEN d.nm IS NULL OR s.nm IS NULL
                   THEN N'-' ELSE N'X' END
  FROM c LEFT JOIN 대장 d ON d.complex_id = c.complex_id
         LEFT JOIN 공간 s ON s.complex_id = c.complex_id
 ORDER BY c.complex_nm;
