SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* 정답(국토부): 필지 → 아파트 거래의 aptSeq(3건 이상) */
IF OBJECT_ID('tempdb..#ps') IS NOT NULL DROP TABLE #ps;
SELECT match_pnu pnu, apt_seq INTO #ps FROM silver.rtms_trade
 WHERE trade_kind LIKE 'APT%' AND trade_kind NOT LIKE 'SILV%' AND apt_seq IS NOT NULL AND match_pnu IS NOT NULL
 GROUP BY match_pnu, apt_seq HAVING COUNT(*) >= 3;
CREATE CLUSTERED INDEX x ON #ps (pnu);
/* 우리 단지(세대 있음) */
IF OBJECT_ID('tempdb..#c') IS NOT NULL DROP TABLE #c;
SELECT complex_id, rep_pnu, lat = CAST(centroid_lat AS FLOAT), lng = CAST(centroid_lng AS FLOAT) INTO #c
  FROM gold.complex WHERE merged_into IS NULL AND hhld_cnt_sum > 0 AND centroid_lat IS NOT NULL;
CREATE CLUSTERED INDEX x ON #c (complex_id);
IF OBJECT_ID('tempdb..#cp') IS NOT NULL DROP TABLE #cp;
SELECT DISTINCT cp.complex_id, cp.pnu INTO #cp FROM gold.complex_pnu cp JOIN #c c ON c.complex_id = cp.complex_id;
CREATE CLUSTERED INDEX x ON #cp (complex_id, pnu); CREATE INDEX y ON #cp (pnu);
/* 단지 → aptSeq 가 딱 하나인 것만 이름표 */
IF OBJECT_ID('tempdb..#lab') IS NOT NULL DROP TABLE #lab;
SELECT cp.complex_id, apt_seq = MIN(s.apt_seq) INTO #lab FROM #cp cp JOIN #ps s ON s.pnu = cp.pnu
 GROUP BY cp.complex_id HAVING COUNT(DISTINCT s.apt_seq) = 1;
CREATE CLUSTERED INDEX x ON #lab (complex_id);
/* 대장 칸(주택 동) */
IF OBJECT_ID('tempdb..#t') IS NOT NULL DROP TABLE #t;
SELECT cb.complex_id, t.mgm_bldrgst_pk, t.pms_day, t.stcns_day, t.use_apr_day, pmsno = CASE WHEN t.pmsno_year IS NOT NULL AND t.pmsno_kik_cd IS NOT NULL THEN CONCAT(t.pmsno_year, '-', t.pmsno_kik_cd, '-', t.pmsno_gb_cd) END,
       road = CASE WHEN t.na_road_cd IS NOT NULL AND TRY_CAST(t.na_main_bun AS INT) > 0 THEN CONCAT(t.na_road_cd, '-', TRY_CAST(t.na_main_bun AS INT)) END
  INTO #t FROM gold.complex_bld cb JOIN #lab l ON l.complex_id = cb.complex_id
  JOIN silver.bld_title t ON t.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND t.is_current = 1 AND t.main_purps_nm LIKE N'%주택%';
CREATE CLUSTERED INDEX x ON #t (complex_id);
IF OBJECT_ID('tempdb..#ca') IS NOT NULL DROP TABLE #ca;
SELECT DISTINCT cb.complex_id, a.atch_pnu INTO #ca FROM gold.complex_bld cb JOIN #lab l ON l.complex_id = cb.complex_id
  JOIN silver.bld_atch_jibun a ON a.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND a.is_current = 1 WHERE a.atch_pnu IS NOT NULL;
CREATE CLUSTERED INDEX x ON #ca (complex_id, atch_pnu);
/* 짝: 같은 aptSeq(정답 묶음) · 다른 aptSeq 이웃(같은 법정동 · 300m 안) */
IF OBJECT_ID('tempdb..#pr') IS NOT NULL DROP TABLE #pr;
SELECT a = l1.complex_id, b = l2.complex_id, 같음 = CASE WHEN l1.apt_seq = l2.apt_seq THEN 1 ELSE 0 END INTO #pr
  FROM #lab l1 JOIN #c c1 ON c1.complex_id = l1.complex_id
  JOIN #c c2 ON LEFT(c2.rep_pnu, 10) = LEFT(c1.rep_pnu, 10) AND c2.complex_id > c1.complex_id
   AND ABS(c2.lat - c1.lat) < 0.0027 AND ABS(c2.lng - c1.lng) < 0.0034
  JOIN #lab l2 ON l2.complex_id = c2.complex_id;
INSERT #pr SELECT l1.complex_id, l2.complex_id, 1 FROM #lab l1 JOIN #lab l2 ON l2.apt_seq = l1.apt_seq AND l2.complex_id > l1.complex_id
 WHERE NOT EXISTS (SELECT 1 FROM #pr p WHERE p.a = l1.complex_id AND p.b = l2.complex_id);
IF OBJECT_ID('tempdb..#f') IS NOT NULL DROP TABLE #f;
SELECT p.*,
  f필지 = CASE WHEN EXISTS (SELECT 1 FROM #cp x JOIN #cp y ON y.pnu = x.pnu WHERE x.complex_id = p.a AND y.complex_id = p.b) THEN 1 ELSE 0 END,
  f부속 = CASE WHEN EXISTS (SELECT 1 FROM #ca x JOIN #cp y ON y.pnu = x.atch_pnu WHERE x.complex_id = p.a AND y.complex_id = p.b)
              OR EXISTS (SELECT 1 FROM #ca x JOIN #cp y ON y.pnu = x.atch_pnu WHERE x.complex_id = p.b AND y.complex_id = p.a)
              OR EXISTS (SELECT 1 FROM #ca x JOIN #ca y ON y.atch_pnu = x.atch_pnu WHERE x.complex_id = p.a AND y.complex_id = p.b) THEN 1 ELSE 0 END,
  f허가일 = CASE WHEN EXISTS (SELECT 1 FROM #t x JOIN #t y ON y.pms_day = x.pms_day WHERE x.complex_id = p.a AND y.complex_id = p.b AND LEN(x.pms_day) = 8) THEN 1 ELSE 0 END,
  f허가번호 = CASE WHEN EXISTS (SELECT 1 FROM #t x JOIN #t y ON y.pmsno = x.pmsno WHERE x.complex_id = p.a AND y.complex_id = p.b) THEN 1 ELSE 0 END,
  f착공일 = CASE WHEN EXISTS (SELECT 1 FROM #t x JOIN #t y ON y.stcns_day = x.stcns_day WHERE x.complex_id = p.a AND y.complex_id = p.b AND LEN(x.stcns_day) >= 6) THEN 1 ELSE 0 END,
  f사용승인 = CASE WHEN EXISTS (SELECT 1 FROM #t x JOIN #t y ON y.use_apr_day = x.use_apr_day WHERE x.complex_id = p.a AND y.complex_id = p.b AND LEN(x.use_apr_day) = 8) THEN 1 ELSE 0 END,
  f도로명 = CASE WHEN EXISTS (SELECT 1 FROM #t x JOIN #t y ON y.road = x.road WHERE x.complex_id = p.a AND y.complex_id = p.b) THEN 1 ELSE 0 END
  INTO #f FROM #pr p;
SELECT 이름표단지 = (SELECT COUNT(*) FROM #lab), 쪼개진정답묶음 = (SELECT COUNT(*) FROM (SELECT apt_seq FROM #lab GROUP BY apt_seq HAVING COUNT(*) > 1) z),
       그안단지 = (SELECT SUM(n) FROM (SELECT n = COUNT(*) FROM #lab GROUP BY apt_seq HAVING COUNT(*) > 1) z);
SELECT 짝 = CASE 같음 WHEN 1 THEN N'같은 단지(정답)' ELSE N'다른 단지 이웃' END, 짝수 = COUNT(*),
       필지 = SUM(f필지), 부속 = SUM(f부속), 필지또는부속 = SUM(CASE WHEN f필지 = 1 OR f부속 = 1 THEN 1 ELSE 0 END),
       허가일 = SUM(f허가일), 허가번호 = SUM(f허가번호), 착공일 = SUM(f착공일), 사용승인 = SUM(f사용승인), 도로명 = SUM(f도로명),
       필지부속_허가일 = SUM(CASE WHEN (f필지 = 1 OR f부속 = 1) AND f허가일 = 1 THEN 1 ELSE 0 END),
       필지부속_허가일또는도로명 = SUM(CASE WHEN (f필지 = 1 OR f부속 = 1) AND (f허가일 = 1 OR f도로명 = 1) THEN 1 ELSE 0 END),
       도로명_허가일 = SUM(CASE WHEN f도로명 = 1 AND f허가일 = 1 THEN 1 ELSE 0 END),
       필지부속_허가일_착공일 = SUM(CASE WHEN (f필지 = 1 OR f부속 = 1) AND f허가일 = 1 AND f착공일 = 1 THEN 1 ELSE 0 END)
  FROM #f GROUP BY 같음;
/* 잘못 묶일 뻔한 예: 다른 aptSeq 인데 필지/부속 + 허가일 같음 */
SELECT TOP 12 p.a, ca.complex_nm, p.b, cb.complex_nm, p.f필지, p.f부속, p.f허가일, p.f도로명, p.f사용승인
  FROM #f p JOIN gold.complex ca ON ca.complex_id = p.a JOIN gold.complex cb ON cb.complex_id = p.b
 WHERE p.같음 = 0 AND (p.f필지 = 1 OR p.f부속 = 1) AND p.f허가일 = 1;
