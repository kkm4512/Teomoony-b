USE Teomoony;
GO
SET NOCOUNT ON;
GO
PRINT '--- cadastral_parcel 컬럼 ---';
SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
 WHERE TABLE_SCHEMA='silver' AND TABLE_NAME='cadastral_parcel' ORDER BY ORDINAL_POSITION;
GO
PRINT '--- 외곽선 없는 단지에 필지 폴리곤이 있나 (150세대+) ---';
WITH c AS (
  SELECT c.complex_id, c.complex_nm, c.hhld_cnt_sum,
         fp = (SELECT COUNT(*) FROM gold.complex_pnu cp
                JOIN silver.building_footprint f ON f.pnu=cp.pnu AND f.is_current=1
               WHERE cp.complex_id=c.complex_id),
         pc = (SELECT COUNT(*) FROM gold.complex_pnu cp
                JOIN silver.cadastral_parcel p ON p.pnu=cp.pnu AND p.is_current=1
               WHERE cp.complex_id=c.complex_id AND p.geojson IS NOT NULL)
    FROM gold.complex c
   WHERE c.sigungu_cd IN ('11110','11290','11380') AND c.hhld_cnt_sum>=150)
SELECT 판정 = CASE WHEN fp>0 THEN N'외곽선 있음(할 일 없음)'
                   WHEN pc>0 THEN N'★ 외곽선은 없지만 필지 폴리곤은 있다 -> 공간교차 가능'
                   ELSE N'필지 폴리곤도 없다' END,
       단지수 = COUNT(*)
  FROM c GROUP BY CASE WHEN fp>0 THEN N'외곽선 있음(할 일 없음)'
                        WHEN pc>0 THEN N'★ 외곽선은 없지만 필지 폴리곤은 있다 -> 공간교차 가능'
                        ELSE N'필지 폴리곤도 없다' END
 ORDER BY 단지수 DESC;
GO
