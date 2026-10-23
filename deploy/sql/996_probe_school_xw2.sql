SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
IF OBJECT_ID('tempdb..#a') IS NOT NULL DROP TABLE #a;
SELECT s.school_id, s.school_nm, s.lat, s.lon, s.fond_date,
       knd = CASE s.school_se WHEN N'초등학교' THEN '02' WHEN N'중학교' THEN '03' WHEN N'고등학교' THEN '04' END,
       fond = REPLACE(s.fond_date, '-', '')
  INTO #a FROM silver.school s
 WHERE s.is_current = 1 AND s.lat IS NOT NULL AND (s.lnmadr LIKE N'서울%' OR s.rdnmadr LIKE N'서울%')
   AND s.school_se IN (N'초등학교', N'중학교', N'고등학교')
   AND NOT EXISTS (SELECT 1 FROM gold.school_link l WHERE l.school_id = s.school_id);
/* 이름 같은 알리미 학교(검산용으로만) — 무엇이 달라서 못 이었나 */
IF OBJECT_ID('tempdb..#n') IS NOT NULL DROP TABLE #n;
SELECT a.school_id, a.school_nm, a.knd, a.fond, i.schul_code, i.knd_code, i.fond_ymd, 개교 = JSON_VALUE(i.raw_json, '$.FOAS_MEMRD'), i.adrcd_cd,
       m = geography::Point(a.lat, a.lon, 4326).STDistance(geography::Point(i.lat, i.lng, 4326)),
       동안 = CASE WHEN EXISTS (SELECT 1 FROM silver.lawd_boundary lb WHERE lb.lawd_cd = i.adrcd_cd AND lb.is_current = 1
                                AND lb.geom.STIntersects(geometry::Point(a.lon, a.lat, lb.geom.STSrid)) = 1) THEN 1 ELSE 0 END
  INTO #n
  FROM #a a JOIN silver.schoolinfo i ON REPLACE(i.schul_nm, ' ', '') = REPLACE(a.school_nm, ' ', '') AND i.lat IS NOT NULL;
SELECT j = (SELECT
  안이음 = (SELECT COUNT(*) FROM #a),
  이름짝 = (SELECT COUNT(DISTINCT school_id) FROM #n),
  급다름 = (SELECT COUNT(*) FROM #n WHERE knd <> knd_code),
  설립일다름 = (SELECT COUNT(*) FROM #n WHERE knd = knd_code AND fond <> fond_ymd),
  설립일다름_개교같음 = (SELECT COUNT(*) FROM #n WHERE knd = knd_code AND fond <> fond_ymd AND fond = 개교),
  동밖 = (SELECT COUNT(*) FROM #n WHERE knd = knd_code AND fond = fond_ymd AND 동안 = 0),
  같은데못이음 = (SELECT COUNT(*) FROM #n WHERE knd = knd_code AND fond = fond_ymd AND 동안 = 1),
  거리분포 = (SELECT b = CASE WHEN m < 50 THEN '0-50' WHEN m < 100 THEN '50-100' WHEN m < 300 THEN '100-300' ELSE '300+' END, n = COUNT(*)
               FROM #n WHERE knd = knd_code GROUP BY CASE WHEN m < 50 THEN '0-50' WHEN m < 100 THEN '50-100' WHEN m < 300 THEN '100-300' ELSE '300+' END FOR JSON PATH),
  보기 = (SELECT TOP 12 school_nm, fond, fond_ymd, 개교, m = CAST(m AS INT), 동안 FROM #n WHERE knd = knd_code ORDER BY school_id FOR JSON PATH)
  FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
