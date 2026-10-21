/* 227_brand_verify : 같은 시점 데이터로 고치기 전/후를 나란히 센다 (2026-10-20) 읽기만 한다 */
USE Teomoony;
GO
SELECT 편의점 = COUNT(*),
  전_브랜드 = SUM(CASE WHEN 음차 IS NOT NULL THEN 1 ELSE 0 END),
  후_브랜드 = SUM(CASE WHEN 음차 IS NOT NULL OR 영문 IS NOT NULL THEN 1 ELSE 0 END),
  전_CU   = SUM(CASE WHEN 음차 = N'CU'   THEN 1 ELSE 0 END),
  후_CU   = SUM(CASE WHEN COALESCE(음차, 영문) = N'CU'   THEN 1 ELSE 0 END),
  전_GS25 = SUM(CASE WHEN 음차 = N'GS25' THEN 1 ELSE 0 END),
  후_GS25 = SUM(CASE WHEN COALESCE(음차, 영문) = N'GS25' THEN 1 ELSE 0 END)
FROM (
  SELECT 음차 = CASE
           WHEN bizes_nm LIKE N'%씨유%'       THEN N'CU'
           WHEN bizes_nm LIKE N'%지에스25%'   THEN N'GS25'
           WHEN bizes_nm LIKE N'%세븐일레븐%' THEN N'세븐일레븐'
           WHEN bizes_nm LIKE N'%이마트24%'   THEN N'이마트24'
           WHEN bizes_nm LIKE N'%미니스톱%'   THEN N'미니스톱' END,
         영문 = CASE
           WHEN bizes_nm LIKE N'%CU%'      THEN N'CU'
           WHEN bizes_nm LIKE N'%GS25%'    THEN N'GS25'
           WHEN bizes_nm LIKE N'%7-ELEVEN%' OR bizes_nm LIKE N'%7ELEVEN%'
             OR bizes_nm LIKE N'%SEVEN ELEVEN%' THEN N'세븐일레븐'
           WHEN bizes_nm LIKE N'%EMART24%' THEN N'이마트24'
           WHEN bizes_nm LIKE N'%MINISTOP%' THEN N'미니스톱' END
    FROM silver.semas_store
   WHERE is_current = 1 AND inds_scls_nm = N'편의점') q;
GO
