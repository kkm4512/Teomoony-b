/* 970 — 좌표 없는 폐쇄 자리: 도로명주소 마스터(325)로 찾을 수 있는가(읽기만) */
SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
IF OBJECT_ID('tempdb..#s') IS NOT NULL DROP TABLE #s;
SELECT s.site_key, s.pnu, 주소 = CAST(LTRIM(RTRIM(s.new_plat_plc)) AS NVARCHAR(300)),
       거래 = (SELECT COUNT(*) FROM silver.rtms_trade r WHERE r.match_pnu = s.pnu AND r.match_complex_id IS NULL AND r.trade_kind NOT LIKE 'SILV%')
  INTO #s FROM gold.closed_site s WHERE s.lat IS NULL AND s.pnu LIKE '11%';
/* ① 대장 도로명주소 = 주소 마스터 도로명주소(글자 그대로 · 괄호 앞까지도) */
IF OBJECT_ID('tempdb..#jj') IS NOT NULL DROP TABLE #jj;
SELECT a = CAST(LEFT(j.road_addr, CHARINDEX(N' (', j.road_addr + N' (') - 1) AS NVARCHAR(300)), b = CAST(j.road_addr AS NVARCHAR(300)), j.pnu
  INTO #jj FROM silver.juso_addr j WHERE j.pnu LIKE '11%' AND j.road_addr IS NOT NULL;
CREATE INDEX ia ON #jj (a); CREATE INDEX ib ON #jj (b);
IF OBJECT_ID('tempdb..#j') IS NOT NULL DROP TABLE #j;
SELECT x.site_key, n = COUNT(DISTINCT x.pnu), pnu = MIN(x.pnu)
  INTO #j FROM (SELECT s.site_key, j.pnu FROM #s s JOIN #jj j ON j.b = s.주소 WHERE s.주소 LIKE N'%[0-9]%'
                UNION SELECT s.site_key, j.pnu FROM #s s JOIN #jj j ON j.a = s.주소 WHERE s.주소 LIKE N'%[0-9]%') x GROUP BY x.site_key;
/* ② 그 자리 실거래의 도로명코드 + 건물번호 = 주소 마스터 */
IF OBJECT_ID('tempdb..#r') IS NOT NULL DROP TABLE #r;
SELECT s.site_key, n = COUNT(DISTINCT j.pnu), pnu = MIN(j.pnu), 거래 = COUNT(DISTINCT r.trade_sk)
  INTO #r FROM #s s JOIN silver.rtms_trade r ON r.match_pnu = s.pnu AND r.match_complex_id IS NULL AND r.road_cd IS NOT NULL AND r.road_bonbun IS NOT NULL
  JOIN silver.juso_addr j ON j.rn_mgt_sn = r.road_cd AND j.buld_mnnm = TRY_CAST(r.road_bonbun AS INT) AND j.buld_slno = ISNULL(TRY_CAST(r.road_bubun AS INT), 0) AND j.udrt_yn = '0'
 GROUP BY s.site_key;
SELECT (SELECT
  자리 = (SELECT COUNT(*) FROM #s), 도로명있음 = (SELECT COUNT(*) FROM #s WHERE 주소 LIKE N'%[0-9]%'),
  거래있는자리 = (SELECT COUNT(*) FROM #s WHERE 거래 > 0), 그거래 = (SELECT SUM(거래) FROM #s),
  주소맞음 = (SELECT COUNT(*) FROM #j), 주소맞음_하나 = (SELECT COUNT(*) FROM #j WHERE n = 1),
  주소맞음_하나_지금필지 = (SELECT COUNT(*) FROM #j JOIN silver.cadastral_parcel p ON p.pnu = #j.pnu AND p.is_current = 1 AND p.centroid_lat IS NOT NULL WHERE #j.n = 1),
  주소맞음_거래 = (SELECT SUM(s.거래) FROM #j JOIN #s s ON s.site_key = #j.site_key JOIN silver.cadastral_parcel p ON p.pnu = #j.pnu AND p.is_current = 1 WHERE #j.n = 1),
  거래길 = (SELECT COUNT(*) FROM #r), 거래길_하나 = (SELECT COUNT(*) FROM #r WHERE n = 1),
  거래길_하나_지금필지 = (SELECT COUNT(*) FROM #r JOIN silver.cadastral_parcel p ON p.pnu = #r.pnu AND p.is_current = 1 AND p.centroid_lat IS NOT NULL WHERE #r.n = 1),
  거래길_거래 = (SELECT SUM(s.거래) FROM #r JOIN #s s ON s.site_key = #r.site_key JOIN silver.cadastral_parcel p ON p.pnu = #r.pnu AND p.is_current = 1 WHERE #r.n = 1),
  둘다_어긋남 = (SELECT COUNT(*) FROM #j JOIN #r ON #r.site_key = #j.site_key WHERE #j.n = 1 AND #r.n = 1 AND #j.pnu <> #r.pnu),
  둘다_같음 = (SELECT COUNT(*) FROM #j JOIN #r ON #r.site_key = #j.site_key WHERE #j.n = 1 AND #r.n = 1 AND #j.pnu = #r.pnu),
  거래길보기 = (SELECT TOP 10 s.site_key, s.주소, r.pnu, r.거래, c.이름 FROM #r r JOIN #s s ON s.site_key = r.site_key JOIN gold.closed_site c ON c.site_key = s.site_key WHERE r.n = 1 ORDER BY r.거래 DESC FOR JSON PATH),
  거래길여럿보기 = (SELECT TOP 5 s.site_key, r.n, r.거래 FROM #r r JOIN #s s ON s.site_key = r.site_key WHERE r.n > 1 ORDER BY r.거래 DESC FOR JSON PATH)
  FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS j;
