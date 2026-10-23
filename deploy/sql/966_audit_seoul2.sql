/* 966_audit_seoul2 — 965 이어서(읽기만). ① K-apt·청약·공시·토지 ② 안 붙은 실거래(필지는 찾음)의 까닭 */
SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
WITH kc AS (SELECT k.kapt_code, k.pnu FROM silver.kapt_complex k WHERE k.is_current = 1 AND k.bjd_code LIKE '11%'),
kl AS (SELECT DISTINCT kapt_code FROM gold.complex_kapt),
ah AS (SELECT DISTINCT p.house_manage_no, p.공고종류 FROM silver.applyhome_pblanc p WHERE p.lawd_cd LIKE '11%' OR p.hssply_adres LIKE N'서울%'),
ahl AS (SELECT DISTINCT house_manage_no FROM gold.applyhome_link),
ah2 AS (SELECT ah.house_manage_no, ah.공고종류, 이음 = CASE WHEN l.house_manage_no IS NULL THEN 0 ELSE 1 END FROM ah LEFT JOIN ahl l ON l.house_manage_no = ah.house_manage_no),
cpn AS (SELECT DISTINCT cp.pnu FROM gold.complex_pnu cp JOIN gold.complex c ON c.complex_id = cp.complex_id WHERE c.is_active = 1 AND c.hhld_cnt_sum > 0 AND cp.pnu LIKE '11%'),
par AS (SELECT pnu FROM silver.cadastral_parcel WHERE is_current = 1 AND pnu LIKE '11%')
SELECT (SELECT
  kapt서울 = (SELECT COUNT(*) FROM kc), kapt이음 = (SELECT COUNT(*) FROM kc JOIN kl ON kl.kapt_code = kc.kapt_code),
  kapt필지없음 = (SELECT COUNT(*) FROM kc WHERE pnu IS NULL),
  청약서울 = (SELECT COUNT(*) FROM ah2), 청약이음 = (SELECT SUM(이음) FROM ah2),
  청약종류 = (SELECT 공고종류, 전체 = COUNT(*), 이음 = SUM(이음) FROM ah2 GROUP BY 공고종류 FOR JSON PATH),
  세대단지필지 = (SELECT COUNT(*) FROM cpn), 공시받음 = (SELECT COUNT(*) FROM cpn JOIN silver.ned_aphus_done d ON d.pnu = cpn.pnu),
  공시값있음 = (SELECT COUNT(*) FROM cpn JOIN silver.ned_aphus_done d ON d.pnu = cpn.pnu WHERE d.건수 > 0),
  필지 = (SELECT COUNT(*) FROM par),
  토지이용받음 = (SELECT COUNT(*) FROM par JOIN silver.land_use_done d ON d.pnu = par.pnu),
  토지이동받음 = (SELECT COUNT(*) FROM par JOIN silver.land_move_done d ON d.pnu = par.pnu),
  토지특성있음 = (SELECT COUNT(*) FROM par WHERE EXISTS (SELECT 1 FROM silver.land_char x WHERE x.pnu = par.pnu AND x.is_current = 1)),
  토지특성연도 = (SELECT base_year, 필지 = COUNT(DISTINCT pnu) FROM silver.land_char WHERE is_current = 1 AND pnu LIKE '11%' GROUP BY base_year FOR JSON PATH),
  용도지역구 = (SELECT layer, 구 = COUNT(DISTINCT sgg_cd) FROM silver.vworld_zone_done WHERE sgg_cd LIKE '11%' GROUP BY layer FOR JSON PATH),
  인허가구 = (SELECT COUNT(DISTINCT sigungu_cd) FROM silver.arch_permit WHERE is_current = 1 AND sigungu_cd LIKE '11%'),
  학교서울 = (SELECT COUNT(*) FROM silver.school WHERE is_current = 1 AND ISNULL(lnmadr, rdnmadr) LIKE N'서울%'),
  역서울 = (SELECT COUNT(*) FROM silver.subway_station WHERE is_current = 1 AND road_addr LIKE N'서울%'),
  세대단지 = (SELECT COUNT(*) FROM gold.complex WHERE is_active = 1 AND hhld_cnt_sum > 0 AND sigungu_cd LIKE '11%'),
  세대단지_역없음 = (SELECT COUNT(*) FROM gold.complex c WHERE c.is_active = 1 AND c.hhld_cnt_sum > 0 AND c.sigungu_cd LIKE '11%' AND c.centroid_lat IS NOT NULL
                     AND NOT EXISTS (SELECT 1 FROM gold.complex_station s WHERE s.complex_id = c.complex_id)),
  세대단지_학교없음 = (SELECT COUNT(*) FROM gold.complex c WHERE c.is_active = 1 AND c.hhld_cnt_sum > 0 AND c.sigungu_cd LIKE '11%' AND c.centroid_lat IS NOT NULL
                     AND NOT EXISTS (SELECT 1 FROM gold.complex_school_near s WHERE s.complex_id = c.complex_id))
  FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS j;
GO
SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
IF OBJECT_ID('tempdb..#u') IS NOT NULL DROP TABLE #u;
SELECT t.trade_sk, t.trade_kind, t.is_rent, t.match_pnu, 연대 = CASE WHEN t.deal_year < 2010 THEN '~2009' WHEN t.deal_year < 2020 THEN '2010s' ELSE '2020~' END
  INTO #u FROM silver.rtms_trade t
 WHERE t.sgg_cd LIKE '11%' AND t.match_complex_id IS NULL AND t.match_pnu IS NOT NULL AND ISNULL(t.jibun_masked, 0) = 0
   AND t.trade_kind IN ('APT_TRADE_DEV', 'APT_RENT', 'RH_TRADE', 'RH_RENT', 'OFFI_TRADE', 'OFFI_RENT');
CREATE INDEX ix ON #u (match_pnu);
IF OBJECT_ID('tempdb..#pc') IS NOT NULL DROP TABLE #pc;
SELECT cp.pnu, 단지 = COUNT(DISTINCT cp.complex_id), 세대단지 = COUNT(DISTINCT CASE WHEN c.hhld_cnt_sum > 0 THEN cp.complex_id END)
  INTO #pc FROM gold.complex_pnu cp JOIN gold.complex c ON c.complex_id = cp.complex_id AND c.is_active = 1
 WHERE cp.pnu IN (SELECT match_pnu FROM #u) GROUP BY cp.pnu;
SELECT (SELECT trade_kind, 연대, 까닭, 행 = COUNT(*), 필지 = COUNT(DISTINCT match_pnu) FROM (
  SELECT u.trade_kind, u.연대, u.match_pnu,
         까닭 = CASE WHEN EXISTS (SELECT 1 FROM ops.rtms_detach_log d WHERE d.trade_sk = u.trade_sk) THEN '1 옛건물로 뗌(329)'
                     WHEN pc.단지 >= 2 THEN '2 한 필지에 단지 여럿'
                     WHEN pc.단지 = 1 AND pc.세대단지 = 1 THEN '3 세대 단지 하나(다른 규칙에 막힘)'
                     WHEN pc.단지 = 1 THEN '4 세대 0 단지 하나'
                     WHEN EXISTS (SELECT 1 FROM gold.closed_site s WHERE s.pnu = u.match_pnu) THEN '5 단지 없음 · 폐쇄 자리 있음'
                     WHEN NOT EXISTS (SELECT 1 FROM silver.cadastral_parcel p WHERE p.pnu = u.match_pnu AND p.is_current = 1) THEN '6 단지 없음 · 지금 필지 아님'
                     ELSE '7 단지 없음 · 필지 있음' END
    FROM #u u LEFT JOIN #pc pc ON pc.pnu = u.match_pnu) x
  GROUP BY trade_kind, 연대, 까닭 ORDER BY trade_kind, 연대, 까닭 FOR JSON PATH) AS j;
