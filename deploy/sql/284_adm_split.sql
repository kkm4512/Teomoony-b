/* 284 : 행정동 '갈림'(연결비율 < 90) 의 **나뉜 내역**을 남긴다 (2026-10-21, 뒷줄 작업 ac-admsplit-bg)
   ★ 왜: 갈린 12곳은 행안부 코드를 하나로 못 고른다(고르면 추측). 대신 사실을 적는다 —
     '상가 자료에서는 신설동 55% · 용두동 45%' 처럼. 그 코드가 **다른 경계의 주인**이면 그 이름도 붙인다
     (경계가 바뀌었는데 상가 쪽 코드가 옛 것이라는 뜻일 가능성이 높다 — 확인은 안 했다).
   ★ 상가수 자체는 경계 안 점을 센 것이라 갈림이어도 맞다. 화면이 그걸 숨기지 않게 한다(server/app).
   ★ 다시 돌려도 된다(UPDATE 만). 276 을 다시 돌리면 이것도 다시 돌린다. */
SET NOCOUNT ON;
GO
IF COL_LENGTH('silver.adm_boundary', '갈림내역') IS NULL
    ALTER TABLE silver.adm_boundary ADD 갈림내역 NVARCHAR(400) NULL;
GO
SET NOCOUNT ON;
UPDATE silver.adm_boundary SET 갈림내역 = NULL;
IF OBJECT_ID('tempdb..#b') IS NOT NULL DROP TABLE #b;
SELECT adm_cd_sgis, year, geom, bbox_minx, bbox_maxx, bbox_miny, bbox_maxy, 상가수 INTO #b
  FROM silver.adm_boundary WHERE 연결비율 < 90;
IF OBJECT_ID('tempdb..#s') IS NOT NULL DROP TABLE #s;
SELECT b.adm_cd_sgis, b.year, st.adong_cd, adong_nm = MAX(st.adong_nm), n = COUNT(*), 합 = MAX(b.상가수)
  INTO #s
  FROM #b b JOIN silver.semas_store st
    ON st.lon BETWEEN b.bbox_minx AND b.bbox_maxx AND st.lat BETWEEN b.bbox_miny AND b.bbox_maxy
   AND b.geom.STContains(geometry::Point(st.lon, st.lat, 4326)) = 1
 WHERE st.is_current = 1 AND st.adong_cd IS NOT NULL
 GROUP BY b.adm_cd_sgis, b.year, st.adong_cd;
WITH r AS (
  SELECT s.*, 주인 = (SELECT TOP 1 a.emd_nm FROM silver.adm_boundary a
                      WHERE a.adm_cd_mois = s.adong_cd AND a.연결비율 >= 90 AND a.adm_cd_sgis <> s.adm_cd_sgis),
         rn = ROW_NUMBER() OVER (PARTITION BY s.adm_cd_sgis, s.year ORDER BY s.n DESC, s.adong_cd)
    FROM #s s)
UPDATE a SET 갈림내역 = x.내역
  FROM silver.adm_boundary a
  JOIN (SELECT adm_cd_sgis, year,
               내역 = STRING_AGG(CONCAT(adong_nm, ' ', CAST(ROUND(100.0 * n / NULLIF(합, 0), 0) AS INT), '%',
                                        CASE WHEN 주인 IS NOT NULL AND 주인 <> adong_nm THEN CONCAT('(지도에선 ', 주인, ')') ELSE '' END),
                                 ' · ') WITHIN GROUP (ORDER BY rn)
          FROM r WHERE rn <= 3 AND 100.0 * n / NULLIF(합, 0) >= 3
         GROUP BY adm_cd_sgis, year) x
    ON x.adm_cd_sgis = a.adm_cd_sgis AND x.year = a.year;
SELECT emd_nm, 연결비율, 갈림내역 FROM silver.adm_boundary WHERE 갈림내역 IS NOT NULL ORDER BY emd_nm;
GO
