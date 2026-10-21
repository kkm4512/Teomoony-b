/* 173. 상호명에 브랜드가 적혀 있나 (2026-10-19) — 읽기 전용 */
SET NOCOUNT ON;
PRINT '--- A. 녹번역 500m 안 편의점 10곳의 실제 상호 ---';
SELECT 상호 = v.bizes_nm, 거리m = CAST(v.dist_m AS INT)
  FROM gold.v_complex_poi v
 WHERE v.complex_id = 95051 AND v.dist_m <= 500 AND v.inds_scls_nm = N'편의점'
 ORDER BY v.dist_m;

PRINT '';
PRINT '--- B. 전체 편의점 1,323곳 상호 표본 ---';
SELECT TOP 15 bizes_nm, 개수 = COUNT(*)
  FROM silver.semas_store WHERE is_current = 1 AND inds_scls_nm = N'편의점'
 GROUP BY bizes_nm ORDER BY COUNT(*) DESC;

PRINT '';
PRINT '--- C. 브랜드가 적힌 비율 (편의점 기준) ---';
SELECT 전체 = COUNT(*),
       브랜드적힘 = SUM(CASE WHEN bizes_nm LIKE N'%GS25%' OR bizes_nm LIKE N'%CU%'
                          OR bizes_nm LIKE N'%세븐일레븐%' OR bizes_nm LIKE N'%이마트24%'
                          OR bizes_nm LIKE N'%미니스톱%' OR bizes_nm LIKE N'%스토리웨이%'
                          THEN 1 ELSE 0 END)
  FROM silver.semas_store WHERE is_current = 1 AND inds_scls_nm = N'편의점';

PRINT '';
PRINT '--- D. 올리브영 62곳은 어디에 (소분류 확인) ---';
SELECT TOP 8 bizes_nm, inds_scls_nm, ldong_nm
  FROM silver.semas_store WHERE is_current = 1 AND bizes_nm LIKE N'%올리브영%'
 ORDER BY bizes_nm;
