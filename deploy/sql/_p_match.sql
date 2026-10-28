SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
IF OBJECT_ID('tempdb..#cp') IS NOT NULL DROP TABLE #cp;
SELECT DISTINCT cp.pnu INTO #cp FROM gold.complex_pnu cp JOIN gold.complex c ON c.complex_id = cp.complex_id AND c.merged_into IS NULL;
CREATE UNIQUE CLUSTERED INDEX ix ON #cp (pnu);
IF OBJECT_ID('tempdb..#bp') IS NOT NULL DROP TABLE #bp;
SELECT DISTINCT mgm_bldrgst_pk INTO #bp FROM gold.complex_bld; CREATE UNIQUE CLUSTERED INDEX ix ON #bp (mgm_bldrgst_pk);
DECLARE @y INT = (SELECT MAX(기준연도) FROM silver.ned_aphus_price);
IF OBJECT_ID('tempdb..#r') IS NOT NULL DROP TABLE #r;
CREATE TABLE #r (순 INT, 자료 NVARCHAR(60), 단위 NVARCHAR(30), 원천 BIGINT, 이어짐 BIGINT, 잇는법 NVARCHAR(80));
INSERT #r SELECT 1, N'실거래 ' + trade_kind, N'거래', COUNT_BIG(*), SUM(CASE WHEN match_complex_id IS NOT NULL THEN 1 ELSE 0 END), N'지번(+K-apt 번호)'
  FROM silver.rtms_trade GROUP BY trade_kind;
INSERT #r SELECT 2, N'K-apt 단지', N'단지', COUNT(DISTINCT k.kapt_code), COUNT(DISTINCT ck.kapt_code), N'지번 · 도로명'
  FROM silver.kapt_complex k LEFT JOIN gold.complex_kapt ck ON ck.kapt_code = k.kapt_code WHERE k.is_current = 1;
INSERT #r SELECT 3, N'관리비(K-apt)', N'단지', COUNT(DISTINCT k.kapt_code), COUNT(DISTINCT ck.kapt_code), N'K-apt 번호'
  FROM (SELECT DISTINCT kapt_code FROM silver.kapt_cost) k LEFT JOIN gold.complex_kapt ck ON ck.kapt_code = k.kapt_code;
INSERT #r SELECT 4, N'건축물대장 표제부', N'건물', COUNT_BIG(*), COUNT_BIG(b.mgm_bldrgst_pk), N'대장 PK'
  FROM silver.bld_title t LEFT JOIN #bp b ON b.mgm_bldrgst_pk = t.mgm_bldrgst_pk WHERE t.is_current = 1;
INSERT #r SELECT 5, N'공동주택가격 ' + CAST(@y AS NVARCHAR(4)) + N'(지번 → 단지)', N'호', COUNT_BIG(*), COUNT_BIG(c.pnu), N'지번'
  FROM silver.ned_aphus_price n LEFT JOIN #cp c ON c.pnu = n.pnu WHERE n.기준연도 = @y;
INSERT #r SELECT 6, N'공동주택가격 → 대장 호', N'호', (SELECT COUNT_BIG(*) FROM silver.ned_aphus_price WHERE 기준연도 = @y), COUNT_BIG(*), N'지번 + 동·호'
  FROM gold.ned_ho_link;
INSERT #r SELECT 7, N'주택가격(대장)', N'건물', COUNT_BIG(*), COUNT_BIG(b.mgm_bldrgst_pk), N'대장 PK'
  FROM silver.bld_hsprc h LEFT JOIN #bp b ON b.mgm_bldrgst_pk = h.mgm_bldrgst_pk WHERE h.is_current = 1;
INSERT #r SELECT 8, N'건축인허가', N'허가', COUNT_BIG(*), COUNT_BIG(c.pnu), N'지번'
  FROM silver.arch_permit a LEFT JOIN #cp c ON c.pnu = a.pnu WHERE a.is_current = 1;
INSERT #r SELECT 9, N'폐쇄대장(옛 단지 → 지금 단지)', N'옛 단지', COUNT_BIG(*), COUNT_BIG(now_complex_id), N'지번'
  FROM gold.closed_site;
INSERT #r SELECT 10, N'청약 공고', N'공고', COUNT(*), (SELECT COUNT(*) FROM (SELECT DISTINCT house_manage_no, pblanc_no FROM gold.applyhome_link WHERE complex_id IS NOT NULL) x), N'지번 · 좌표'
  FROM (SELECT DISTINCT house_manage_no, pblanc_no FROM silver.applyhome_pblanc) p;
INSERT #r SELECT 11, N'정비구역', N'구역', COUNT(DISTINCT z.present_sn), COUNT(DISTINCT h.present_sn), N'경계 겹침'
  FROM silver.redev_zone z LEFT JOIN gold.complex_redev_hit h ON h.present_sn = z.present_sn WHERE z.is_current = 1;
INSERT #r SELECT 12, N'상가(점포가 단지 필지 안)', N'점포', COUNT_BIG(*), COUNT_BIG(c.pnu), N'지번'
  FROM silver.semas_store s LEFT JOIN #cp c ON c.pnu = s.pnu WHERE s.is_current = 1;
INSERT #r SELECT 13, N'학교알리미 ↔ 학교 위치', N'학교', COUNT(DISTINCT s.schul_code), COUNT(DISTINCT l.schul_code), N'학교 코드'
  FROM silver.schoolinfo s LEFT JOIN gold.school_link l ON l.schul_code = s.schul_code;
SELECT 자료, 단위, 원천, 이어짐, 률 = CAST(100.0 * 이어짐 / NULLIF(원천, 0) AS DECIMAL(5,1)), 잇는법 FROM #r ORDER BY 순, 자료;
/* 단지 쪽 */
IF OBJECT_ID('tempdb..#np') IS NOT NULL DROP TABLE #np;
SELECT DISTINCT p.complex_id INTO #np FROM gold.complex_pnu p WHERE p.pnu IN (SELECT DISTINCT pnu FROM silver.ned_aphus_price);
IF OBJECT_ID('tempdb..#ap') IS NOT NULL DROP TABLE #ap;
SELECT DISTINCT p.complex_id INTO #ap FROM gold.complex_pnu p WHERE p.pnu IN (SELECT pnu FROM silver.arch_permit WHERE is_current = 1);
IF OBJECT_ID('tempdb..#lc') IS NOT NULL DROP TABLE #lc;
SELECT DISTINCT pnu INTO #lc FROM silver.land_char WHERE is_current = 1;
IF OBJECT_ID('tempdb..#lu') IS NOT NULL DROP TABLE #lu;
SELECT DISTINCT pnu INTO #lu FROM silver.land_use_plan WHERE is_current = 1;
IF OBJECT_ID('tempdb..#ck') IS NOT NULL DROP TABLE #ck;
SELECT DISTINCT complex_id INTO #ck FROM gold.complex_kapt;
SELECT 묶음 = CASE WHEN c.hhld_cnt_sum >= 20 THEN N'20세대+' ELSE N'그 밖' END, 단지 = COUNT(*),
       실거래 = SUM(CASE WHEN ISNULL(c.trade_cnt,0) + ISNULL(c.rent_cnt,0) > 0 THEN 1 ELSE 0 END),
       Kapt = COUNT(ck.complex_id), 공동주택가격 = COUNT(np.complex_id), 토지특성 = COUNT(lc.pnu), 토지이용계획 = COUNT(lu.pnu), 건축인허가 = COUNT(ap.complex_id)
  FROM gold.complex c
  LEFT JOIN #ck ck ON ck.complex_id = c.complex_id LEFT JOIN #np np ON np.complex_id = c.complex_id LEFT JOIN #ap ap ON ap.complex_id = c.complex_id
  LEFT JOIN #lc lc ON lc.pnu = c.rep_pnu LEFT JOIN #lu lu ON lu.pnu = c.rep_pnu
 WHERE c.merged_into IS NULL
 GROUP BY CASE WHEN c.hhld_cnt_sum >= 20 THEN N'20세대+' ELSE N'그 밖' END;
