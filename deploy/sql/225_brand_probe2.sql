/* 225_brand_probe2 : CU / GS25 영문 패턴이 편의점 밖에서 헛걸리나 (2026-10-20) 읽기만 한다 */
USE Teomoony;
GO
PRINT '--- 1) 편의점이 아닌데 CU 또는 GS25 가 들어간 상호는 몇 건인가 ---';
SELECT CU밖 = SUM(CASE WHEN bizes_nm LIKE N'%CU%'   AND bizes_nm NOT LIKE N'%씨유%'     THEN 1 ELSE 0 END),
       GS밖 = SUM(CASE WHEN bizes_nm LIKE N'%GS25%' AND bizes_nm NOT LIKE N'%지에스25%' THEN 1 ELSE 0 END),
       CU앞 = SUM(CASE WHEN bizes_nm LIKE N'CU%'    AND bizes_nm NOT LIKE N'%씨유%'     THEN 1 ELSE 0 END)
  FROM silver.semas_store
 WHERE is_current = 1 AND (inds_scls_nm <> N'편의점' OR inds_scls_nm IS NULL);
GO
PRINT '--- 2) 그 상호들을 눈으로 본다 (CU) ---';
SELECT 보기 = STRING_AGG(nm, N' | ') FROM (
  SELECT TOP 30 nm = bizes_nm + N'(' + ISNULL(inds_scls_nm, N'?') + N')'
    FROM silver.semas_store
   WHERE is_current = 1 AND (inds_scls_nm <> N'편의점' OR inds_scls_nm IS NULL)
     AND bizes_nm LIKE N'%CU%' AND bizes_nm NOT LIKE N'%씨유%'
   GROUP BY bizes_nm, inds_scls_nm ORDER BY COUNT(*) DESC) t;
GO
PRINT '--- 3) 그 상호들을 눈으로 본다 (GS25) ---';
SELECT 보기 = STRING_AGG(nm, N' | ') FROM (
  SELECT TOP 30 nm = bizes_nm + N'(' + ISNULL(inds_scls_nm, N'?') + N')'
    FROM silver.semas_store
   WHERE is_current = 1 AND (inds_scls_nm <> N'편의점' OR inds_scls_nm IS NULL)
     AND bizes_nm LIKE N'%GS25%' AND bizes_nm NOT LIKE N'%지에스25%'
   GROUP BY bizes_nm, inds_scls_nm ORDER BY COUNT(*) DESC) t;
GO
PRINT '--- 4) 편의점 안에서 CU 영문이 CU 로 시작하지 않는 것 (헛걸림 후보) ---';
SELECT 보기 = ISNULL(STRING_AGG(nm, N' | '), N'(없음)') FROM (
  SELECT TOP 30 nm = bizes_nm FROM silver.semas_store
   WHERE is_current = 1 AND inds_scls_nm = N'편의점'
     AND bizes_nm LIKE N'%CU%' AND bizes_nm NOT LIKE N'CU%' AND bizes_nm NOT LIKE N'%씨유%'
   GROUP BY bizes_nm ORDER BY COUNT(*) DESC) t;
GO
