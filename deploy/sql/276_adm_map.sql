/* 276. 행정동 경계(SGIS 코드) ↔ 행정안전부 행정동 코드 — **상가 점의 위치**로 잇는다 (2026-10-21)
   ★ 왜 위치인가: 두 코드는 체계가 다르고(성북 11080 vs 11290) 공식 대응표를 API 로 못 받는다.
     이름으로 이으면 정책 1장 위반이다. 상가(semas_store)는 점마다 행안부 adong_cd 를 들고 있다 —
     SGIS 경계 안에 떨어진 상가들이 **어느 코드를 가장 많이 들고 있나**를 센다.
   ★ 근거를 남긴다: 연결상가 / 상가수 / 연결비율. 비율이 낮으면 화면이 '추정' 이라고 적어야 한다.
     경계선 근처 점(좌표 오차)이 섞이므로 100% 는 기대하지 않는다.
   ★ 다시 돌려도 된다(UPDATE 만). */
SET NOCOUNT ON;
GO
UPDATE silver.adm_boundary SET adm_cd_mois = NULL, mois_nm = NULL, 연결근거 = NULL,
       연결상가 = NULL, 상가수 = NULL, 연결비율 = NULL;
GO
DECLARE @t DATETIME2 = SYSDATETIME();
WITH s AS (
    SELECT a.adm_cd_sgis, a.year, st.adong_cd, adong_nm = MAX(st.adong_nm), n = COUNT(*)
      FROM silver.semas_store st
      JOIN silver.adm_boundary a
        ON a.bbox_minx <= st.lon AND a.bbox_maxx >= st.lon
       AND a.bbox_miny <= st.lat AND a.bbox_maxy >= st.lat
       AND a.geom.STContains(geometry::Point(st.lon, st.lat, 4326)) = 1
     WHERE st.is_current = 1 AND st.lon IS NOT NULL AND st.lat IS NOT NULL AND st.adong_cd IS NOT NULL
     GROUP BY a.adm_cd_sgis, a.year, st.adong_cd),
r AS (
    SELECT *, 합 = SUM(n) OVER (PARTITION BY adm_cd_sgis, year),
           rn = ROW_NUMBER() OVER (PARTITION BY adm_cd_sgis, year ORDER BY n DESC, adong_cd)
      FROM s)
UPDATE a SET adm_cd_mois = r.adong_cd, mois_nm = r.adong_nm, 연결근거 = N'상가 위치 다수결',
       연결상가 = r.n, 상가수 = r.합, 연결비율 = CAST(100.0 * r.n / r.합 AS DECIMAL(5,2))
  FROM silver.adm_boundary a JOIN r ON r.adm_cd_sgis = a.adm_cd_sgis AND r.year = a.year AND r.rn = 1;
PRINT CONCAT('잇기 (초) = ', DATEDIFF(SECOND, @t, SYSDATETIME()));
GO
PRINT '--- 결과 ---';
SELECT 경계 = COUNT(*), 이어짐 = COUNT(adm_cd_mois),
       비율_99이상 = SUM(CASE WHEN 연결비율 >= 99 THEN 1 ELSE 0 END),
       비율_95이상 = SUM(CASE WHEN 연결비율 >= 95 THEN 1 ELSE 0 END),
       비율_90미만 = SUM(CASE WHEN 연결비율 < 90 THEN 1 ELSE 0 END),
       최저비율 = MIN(연결비율), 상가합 = SUM(상가수)
  FROM silver.adm_boundary;
GO
PRINT '--- 한 행안부 코드에 경계가 둘 이상 붙은 것 (있으면 안 된다) ---';
SELECT adm_cd_mois, 경계수 = COUNT(*), 이름들 = STRING_AGG(emd_nm, ', ')
  FROM silver.adm_boundary WHERE adm_cd_mois IS NOT NULL
 GROUP BY adm_cd_mois HAVING COUNT(*) > 1;
GO
PRINT '--- 이름 대조 (확인용일 뿐 - 잇는 데 안 썼다) ---';
SELECT 이름같음 = SUM(CASE WHEN REPLACE(emd_nm, N'·', N'.') = REPLACE(mois_nm, N'·', N'.') THEN 1 ELSE 0 END),
       이름다름 = SUM(CASE WHEN mois_nm IS NOT NULL AND REPLACE(emd_nm, N'·', N'.') <> REPLACE(mois_nm, N'·', N'.') THEN 1 ELSE 0 END)
  FROM silver.adm_boundary;
GO
PRINT '--- 이름이 다르거나 비율 낮은 것 (최대 15) ---';
SELECT TOP 15 adm_cd_sgis, emd_nm, adm_cd_mois, mois_nm, 연결상가, 상가수, 연결비율
  FROM silver.adm_boundary
 WHERE adm_cd_mois IS NULL OR 연결비율 < 95 OR REPLACE(emd_nm, N'·', N'.') <> REPLACE(mois_nm, N'·', N'.')
 ORDER BY 연결비율;
GO
PRINT '276 완료';
