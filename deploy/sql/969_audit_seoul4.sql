/* 969 — 청약 안 이어진 것 · 기타(읽기만) */
SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
IF OBJECT_ID('tempdb..#a') IS NOT NULL DROP TABLE #a;
SELECT p.house_manage_no, 공고종류 = MAX(p.공고종류), 이름 = MAX(p.house_nm), pnu = MAX(p.pnu), 입주 = MAX(p.mvn_prearnge_ym), 공고일 = MAX(p.rcrit_pblanc_de),
       세부 = MAX(p.house_dtl_secd_nm), 공급 = MAX(p.tot_suply), 주소 = MAX(p.hssply_adres)
  INTO #a FROM silver.applyhome_pblanc p
 WHERE (p.lawd_cd LIKE '11%' OR p.hssply_adres LIKE N'서울%') AND NOT EXISTS (SELECT 1 FROM gold.applyhome_link l WHERE l.house_manage_no = p.house_manage_no)
 GROUP BY p.house_manage_no;
ALTER TABLE #a ADD 입주앞 NVARCHAR(10), 필지 NVARCHAR(10), 폐쇄 BIT;
UPDATE a SET 입주앞 = CASE WHEN 입주 IS NULL THEN N'모름' WHEN 입주 > FORMAT(SYSDATETIME(), 'yyyyMM') THEN N'입주 전' ELSE N'입주 지남' END,
             필지 = CASE WHEN pnu IS NULL THEN N'없음' WHEN n.k = 0 THEN N'단지 없음' WHEN n.k >= 2 THEN N'단지 여럿' ELSE N'단지 하나' END,
             폐쇄 = CASE WHEN EXISTS (SELECT 1 FROM gold.closed_site s WHERE s.pnu = a.pnu) THEN 1 ELSE 0 END
  FROM #a a OUTER APPLY (SELECT k = COUNT(DISTINCT cp.complex_id) FROM gold.complex_pnu cp JOIN gold.complex c ON c.complex_id = cp.complex_id AND c.is_active = 1 WHERE cp.pnu = a.pnu) n;
SELECT (SELECT
  묶음 = (SELECT 공고종류, 입주앞, 필지, 폐쇄, n = COUNT(*) FROM #a GROUP BY 공고종류, 입주앞, 필지, 폐쇄 ORDER BY 공고종류, COUNT(*) DESC FOR JSON PATH),
  보기 = (SELECT TOP 25 house_manage_no, 공고종류, 이름, pnu, 입주, 공고일, 공급, 필지, 폐쇄, 주소 FROM #a WHERE 입주앞 = N'입주 지남' ORDER BY 공급 DESC FOR JSON PATH)
  FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS j;
GO
SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
IF OBJECT_ID('tempdb..#x') IS NOT NULL DROP TABLE #x;
SELECT c.complex_id, 세대 = CASE WHEN c.hhld_cnt_sum > 0 THEN 1 ELSE 0 END, 이름 = c.complex_nm_src,
       대표필지지금 = CASE WHEN EXISTS (SELECT 1 FROM silver.cadastral_parcel p WHERE p.pnu = c.rep_pnu AND p.is_current = 1) THEN 1 ELSE 0 END,
       아무필지지금 = CASE WHEN EXISTS (SELECT 1 FROM gold.complex_pnu cp JOIN silver.cadastral_parcel p ON p.pnu = cp.pnu AND p.is_current = 1 WHERE cp.complex_id = c.complex_id) THEN 1 ELSE 0 END
  INTO #x FROM gold.complex c WHERE c.is_active = 1 AND c.sigungu_cd LIKE '11%' AND c.centroid_lat IS NULL;
SELECT (SELECT
  거래보기 = (SELECT TOP 20 t.trade_kind, t.match_pnu, t.bld_nm, n = COUNT(*), 처음 = MIN(t.deal_ymd), 끝 = MAX(t.deal_ymd),
                     지금대장 = (SELECT TOP 1 b.main_purps_nm + N' · ' + ISNULL(b.bld_nm, '') + N' · ' + ISNULL(b.use_apr_day, '') FROM silver.bld_title b WHERE b.pnu = t.match_pnu AND b.is_current = 1 ORDER BY b.hhld_cnt DESC),
                     기본개요 = (SELECT COUNT(*) FROM silver.bld_basis_outline b WHERE b.pnu = t.match_pnu AND b.is_current = 1)
                FROM silver.rtms_trade t
               WHERE t.sgg_cd LIKE '11%' AND t.match_complex_id IS NULL AND t.match_pnu IS NOT NULL AND ISNULL(t.jibun_masked, 0) = 0
                 AND t.trade_kind IN ('APT_TRADE_DEV', 'RH_TRADE', 'OFFI_TRADE', 'OFFI_RENT', 'APT_RENT', 'RH_RENT')
                 AND NOT EXISTS (SELECT 1 FROM gold.complex_pnu cp WHERE cp.pnu = t.match_pnu)
                 AND NOT EXISTS (SELECT 1 FROM gold.closed_site s WHERE s.pnu = t.match_pnu)
                 AND EXISTS (SELECT 1 FROM silver.cadastral_parcel p WHERE p.pnu = t.match_pnu AND p.is_current = 1)
               GROUP BY t.trade_kind, t.match_pnu, t.bld_nm ORDER BY COUNT(*) DESC FOR JSON PATH),
  좌표없는단지 = (SELECT 세대, 이름, 대표필지지금, 아무필지지금, n = COUNT(*) FROM #x GROUP BY 세대, 이름, 대표필지지금, 아무필지지금 FOR JSON PATH),
  세대좌표없음보기 = (SELECT TOP 15 c.complex_id, c.complex_nm, c.rep_pnu, c.rep_plat_plc, c.hhld_cnt_sum, c.oldest_use_apr FROM gold.complex c
                      WHERE c.is_active = 1 AND c.sigungu_cd LIKE '11%' AND c.centroid_lat IS NULL AND c.hhld_cnt_sum > 0 ORDER BY c.hhld_cnt_sum DESC FOR JSON PATH),
  폐쇄상세 = (SELECT t.차례, 대상 = COUNT(*), 받음 = SUM(CASE WHEN d.pnu IS NULL THEN 0 ELSE 1 END)
               FROM gold.v_closed_detail_target t LEFT JOIN (SELECT DISTINCT pnu FROM silver.bld_closed_detail_done) d ON d.pnu = t.pnu WHERE t.pnu LIKE '11%' GROUP BY t.차례 FOR JSON PATH),
  폐쇄공시 = (SELECT 대상 = COUNT(*), 받음 = SUM(CASE WHEN d.pnu IS NULL THEN 0 ELSE 1 END)
               FROM gold.v_closed_detail_target t LEFT JOIN silver.ned_aphus_done d ON d.pnu = t.pnu WHERE t.pnu LIKE '11%' FOR JSON PATH),
  둔촌자리 = (SELECT TOP 8 s.site_key, s.이름, s.pnu, s.폐쇄구분, s.shter_day, s.총괄세대, s.lat FROM gold.closed_site s
               WHERE s.pnu LIKE (SELECT TOP 1 lawd_cd FROM meta.lawd_code WHERE sgg_cd = '11740' AND emd_nm = N'둔촌동' AND ri_nm IS NULL) + '%' ORDER BY s.총괄세대 DESC FOR JSON PATH),
  둔촌표제 = (SELECT TOP 8 t.pnu, t.bld_nm, t.dong_nm, t.shter_day, t.shter_gb_nm, t.regstr_gb_nm FROM silver.bld_closed_title t WHERE t.bld_nm LIKE N'%둔촌%' FOR JSON PATH)
  FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS j;
