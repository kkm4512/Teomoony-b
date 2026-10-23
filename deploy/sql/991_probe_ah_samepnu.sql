SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
IF OBJECT_ID('tempdb..#h') IS NOT NULL DROP TABLE #h;
SELECT p.house_manage_no, pnu = MAX(p.pnu), mvn = MAX(p.mvn_prearnge_ym), nm = MAX(p.house_nm), 종류 = MAX(p.공고종류),
       첫 = MIN(p.rcrit_pblanc_de), 링크 = MAX(CASE WHEN l.house_manage_no IS NOT NULL THEN 1 ELSE 0 END)
  INTO #h
  FROM silver.applyhome_pblanc p
  LEFT JOIN gold.applyhome_link l ON l.house_manage_no = p.house_manage_no
 WHERE p.pnu LIKE '11%'
 GROUP BY p.house_manage_no;
IF OBJECT_ID('tempdb..#g') IS NOT NULL DROP TABLE #g;
SELECT pnu, 집 = COUNT(*), 입주월 = COUNT(DISTINCT mvn), 미연결 = SUM(CASE WHEN 링크 = 0 THEN 1 ELSE 0 END), 연결 = SUM(링크),
       이름 = COUNT(DISTINCT nm)
  INTO #g FROM #h WHERE pnu IS NOT NULL GROUP BY pnu;
SELECT j = (SELECT
  필지 = (SELECT COUNT(*) FROM #g),
  여럿 = (SELECT COUNT(*) FROM #g WHERE 집 > 1),
  여럿_입주월여럿 = (SELECT COUNT(*) FROM #g WHERE 집 > 1 AND 입주월 > 1),
  여럿_미연결만 = (SELECT COUNT(*) FROM #g WHERE 집 > 1 AND 연결 = 0),
  여럿_섞임 = (SELECT COUNT(*) FROM #g WHERE 집 > 1 AND 연결 > 0 AND 미연결 > 0),
  보기_입주월여럿 = (SELECT TOP 15 h.pnu, h.house_manage_no, h.nm, h.종류, h.mvn, h.첫, h.링크 FROM #h h
                     WHERE h.pnu IN (SELECT TOP 5 pnu FROM #g WHERE 집 > 1 AND 입주월 > 1 ORDER BY pnu) ORDER BY h.pnu, h.첫 FOR JSON PATH),
  보기_이름다름 = (SELECT TOP 15 h.pnu, h.house_manage_no, h.nm, h.종류, h.mvn, h.첫, h.링크 FROM #h h
                     WHERE h.pnu IN (SELECT TOP 5 pnu FROM #g WHERE 집 > 1 AND 입주월 = 1 AND 이름 > 1 AND 연결 = 0 ORDER BY pnu) ORDER BY h.pnu, h.첫 FOR JSON PATH),
  보기_섞임 = (SELECT TOP 15 h.pnu, h.house_manage_no, h.nm, h.종류, h.mvn, h.첫, h.링크 FROM #h h
                     WHERE h.pnu IN (SELECT TOP 5 pnu FROM #g WHERE 집 > 1 AND 연결 > 0 AND 미연결 > 0 ORDER BY pnu) ORDER BY h.pnu, h.첫 FOR JSON PATH)
  FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
