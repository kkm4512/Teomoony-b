/* 967_audit_seoul3 — 서울 매칭 빈칸 까닭(읽기만) */
SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* 1 폐쇄 자리 좌표 없음: 지금 필지인가 · 토지이동 마지막 사유(숫자 지움) */
IF OBJECT_ID('tempdb..#c') IS NOT NULL DROP TABLE #c;
SELECT s.site_key, s.pnu, s.이름, s.총괄세대,
       지금필지 = CASE WHEN EXISTS (SELECT 1 FROM silver.cadastral_parcel p WHERE p.pnu = s.pnu AND p.is_current = 1) THEN 1 ELSE 0 END,
       이동받음 = CASE WHEN EXISTS (SELECT 1 FROM silver.land_move_done d WHERE d.pnu = s.pnu) THEN 1 ELSE 0 END,
       사유 = (SELECT TOP 1 x.이동사유 FROM silver.land_move_hist x WHERE x.pnu = s.pnu ORDER BY x.이동일 DESC, x.이력순번 DESC),
       거래 = (SELECT COUNT(*) FROM silver.rtms_trade r WHERE r.match_pnu = s.pnu AND r.match_complex_id IS NULL AND r.trade_kind NOT LIKE 'SILV%')
  INTO #c FROM gold.closed_site s WHERE s.lat IS NULL AND s.pnu LIKE '11%';
SELECT (SELECT 지금필지, 이동받음, 사유꼴 = LEFT(TRANSLATE(ISNULL(사유, N'(이력 없음)'), '0123456789', '##########'), 40), 자리 = COUNT(*), 거래있는자리 = SUM(CASE WHEN 거래 > 0 THEN 1 ELSE 0 END), 거래 = SUM(거래)
          FROM #c GROUP BY 지금필지, 이동받음, LEFT(TRANSLATE(ISNULL(사유, N'(이력 없음)'), '0123456789', '##########'), 40)
         ORDER BY COUNT(*) DESC OFFSET 0 ROWS FETCH NEXT 40 ROWS ONLY FOR JSON PATH) AS j;
GO
SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* 2 K-apt 안 이어진 것 */
IF OBJECT_ID('tempdb..#k') IS NOT NULL DROP TABLE #k;
SELECT k.kapt_code, k.kapt_name, k.pnu, k.kapt_usedate, k.ho_cnt, k.code_sale_nm,
       신축 = CASE WHEN EXISTS (SELECT 1 FROM gold.v_newbuild n WHERE n.kapt_code = k.kapt_code) THEN 1 ELSE 0 END,
       필지단지 = (SELECT COUNT(DISTINCT cp.complex_id) FROM gold.complex_pnu cp JOIN gold.complex c ON c.complex_id = cp.complex_id AND c.is_active = 1 WHERE cp.pnu = k.pnu),
       필지세대단지 = (SELECT COUNT(DISTINCT cp.complex_id) FROM gold.complex_pnu cp JOIN gold.complex c ON c.complex_id = cp.complex_id AND c.is_active = 1 AND c.hhld_cnt_sum > 0 WHERE cp.pnu = k.pnu),
       폐쇄 = CASE WHEN EXISTS (SELECT 1 FROM gold.closed_site s WHERE s.pnu = k.pnu) THEN 1 ELSE 0 END
  INTO #k FROM silver.kapt_complex k
 WHERE k.is_current = 1 AND k.bjd_code LIKE '11%' AND NOT EXISTS (SELECT 1 FROM gold.complex_kapt x WHERE x.kapt_code = k.kapt_code);
SELECT (SELECT
  묶음 = (SELECT 신축, 필지없음 = CASE WHEN pnu IS NULL THEN 1 ELSE 0 END, 필지세대단지 = CASE WHEN 필지세대단지 >= 2 THEN 2 ELSE 필지세대단지 END, 폐쇄, n = COUNT(*)
            FROM #k GROUP BY 신축, CASE WHEN pnu IS NULL THEN 1 ELSE 0 END, CASE WHEN 필지세대단지 >= 2 THEN 2 ELSE 필지세대단지 END, 폐쇄 FOR JSON PATH),
  보기 = (SELECT TOP 25 kapt_code, kapt_name, pnu, kapt_usedate, ho_cnt, 신축, 필지단지, 필지세대단지, 폐쇄 FROM #k WHERE 신축 = 0 ORDER BY ho_cnt DESC FOR JSON PATH)
  FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS j;
GO
SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* 3 청약 안 이어진 것 */
IF OBJECT_ID('tempdb..#a') IS NOT NULL DROP TABLE #a;
SELECT p.house_manage_no, 공고종류 = MAX(p.공고종류), 이름 = MAX(p.house_nm), pnu = MAX(p.pnu), 입주 = MAX(p.mvn_prearnge_ym), 공고일 = MAX(p.rcrit_pblanc_de),
       세부 = MAX(p.house_dtl_secd_nm), 공급 = MAX(p.tot_suply)
  INTO #a FROM silver.applyhome_pblanc p
 WHERE (p.lawd_cd LIKE '11%' OR p.hssply_adres LIKE N'서울%') AND NOT EXISTS (SELECT 1 FROM gold.applyhome_link l WHERE l.house_manage_no = p.house_manage_no)
 GROUP BY p.house_manage_no;
SELECT (SELECT
  묶음 = (SELECT 공고종류, 입주앞 = CASE WHEN 입주 IS NULL THEN '모름' WHEN 입주 > FORMAT(SYSDATETIME(), 'yyyyMM') THEN '입주 전' ELSE '입주 지남' END,
                필지 = CASE WHEN pnu IS NULL THEN '없음'
                            WHEN NOT EXISTS (SELECT 1 FROM gold.complex_pnu cp WHERE cp.pnu = a.pnu) THEN '단지 없음'
                            WHEN (SELECT COUNT(DISTINCT cp.complex_id) FROM gold.complex_pnu cp JOIN gold.complex c ON c.complex_id = cp.complex_id AND c.is_active = 1 WHERE cp.pnu = a.pnu) >= 2 THEN '단지 여럿'
                            ELSE '단지 하나' END,
                n = COUNT(*)
            FROM #a a GROUP BY 공고종류, CASE WHEN 입주 IS NULL THEN '모름' WHEN 입주 > FORMAT(SYSDATETIME(), 'yyyyMM') THEN '입주 전' ELSE '입주 지남' END,
                 CASE WHEN pnu IS NULL THEN '없음'
                            WHEN NOT EXISTS (SELECT 1 FROM gold.complex_pnu cp WHERE cp.pnu = a.pnu) THEN '단지 없음'
                            WHEN (SELECT COUNT(DISTINCT cp.complex_id) FROM gold.complex_pnu cp JOIN gold.complex c ON c.complex_id = cp.complex_id AND c.is_active = 1 WHERE cp.pnu = a.pnu) >= 2 THEN '단지 여럿'
                            ELSE '단지 하나' END
           ORDER BY 공고종류, COUNT(*) DESC FOR JSON PATH),
  보기 = (SELECT TOP 20 a.* FROM #a a WHERE 입주 <= FORMAT(SYSDATETIME(), 'yyyyMM') AND 공고종류 = 'APT' ORDER BY 공급 DESC FOR JSON PATH)
  FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS j;
GO
SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* 4 기타: 단지 없음·필지 있음 거래 보기 · 좌표 없는 단지 · 폐쇄 상세 대상 · 둔촌 · NED 남음 */
SELECT (SELECT
  거래보기 = (SELECT TOP 20 t.trade_kind, t.match_pnu, t.bld_nm, t.deal_year, n = COUNT(*),
                     지금대장 = (SELECT TOP 1 b.main_purps_nm + N' · ' + ISNULL(b.bld_nm, '') FROM silver.bld_title b WHERE b.pnu = t.match_pnu AND b.is_current = 1 ORDER BY b.hhld_cnt DESC),
                     기본개요 = (SELECT COUNT(*) FROM silver.bld_basis_outline b WHERE b.pnu = t.match_pnu AND b.is_current = 1)
                FROM silver.rtms_trade t
               WHERE t.sgg_cd LIKE '11%' AND t.match_complex_id IS NULL AND t.match_pnu IS NOT NULL AND ISNULL(t.jibun_masked, 0) = 0
                 AND t.trade_kind IN ('APT_TRADE_DEV', 'RH_TRADE', 'OFFI_TRADE', 'OFFI_RENT', 'APT_RENT')
                 AND NOT EXISTS (SELECT 1 FROM gold.complex_pnu cp WHERE cp.pnu = t.match_pnu)
                 AND NOT EXISTS (SELECT 1 FROM gold.closed_site s WHERE s.pnu = t.match_pnu)
                 AND EXISTS (SELECT 1 FROM silver.cadastral_parcel p WHERE p.pnu = t.match_pnu AND p.is_current = 1)
               GROUP BY t.trade_kind, t.match_pnu, t.bld_nm, t.deal_year ORDER BY COUNT(*) DESC FOR JSON PATH),
  좌표없는단지 = (SELECT 세대 = CASE WHEN c.hhld_cnt_sum > 0 THEN 1 ELSE 0 END, 이름 = c.complex_nm_src,
                        대표필지지금 = CASE WHEN EXISTS (SELECT 1 FROM silver.cadastral_parcel p WHERE p.pnu = c.rep_pnu AND p.is_current = 1) THEN 1 ELSE 0 END, n = COUNT(*)
                   FROM gold.complex c WHERE c.is_active = 1 AND c.sigungu_cd LIKE '11%' AND c.centroid_lat IS NULL
                  GROUP BY CASE WHEN c.hhld_cnt_sum > 0 THEN 1 ELSE 0 END, c.complex_nm_src,
                           CASE WHEN EXISTS (SELECT 1 FROM silver.cadastral_parcel p WHERE p.pnu = c.rep_pnu AND p.is_current = 1) THEN 1 ELSE 0 END FOR JSON PATH),
  세대좌표없음보기 = (SELECT TOP 15 c.complex_id, c.complex_nm, c.rep_pnu, c.rep_plat_plc, c.hhld_cnt_sum, c.oldest_use_apr FROM gold.complex c
                      WHERE c.is_active = 1 AND c.sigungu_cd LIKE '11%' AND c.centroid_lat IS NULL AND c.hhld_cnt_sum > 0 ORDER BY c.hhld_cnt_sum DESC FOR JSON PATH),
  폐쇄상세 = (SELECT t.차례, 대상 = COUNT(*), 받음 = SUM(CASE WHEN EXISTS (SELECT 1 FROM silver.bld_closed_detail_done d WHERE d.pnu = t.pnu) THEN 1 ELSE 0 END)
               FROM gold.v_closed_detail_target t WHERE t.pnu LIKE '11%' GROUP BY t.차례 FOR JSON PATH),
  폐쇄공시 = (SELECT 대상 = COUNT(*), 받음 = SUM(CASE WHEN EXISTS (SELECT 1 FROM silver.ned_aphus_done d WHERE d.pnu = t.pnu) THEN 1 ELSE 0 END)
               FROM gold.v_closed_detail_target t WHERE t.pnu LIKE '11%' FOR JSON PATH),
  둔촌자리 = (SELECT TOP 8 s.site_key, s.이름, s.pnu, s.폐쇄구분, s.shter_day, s.총괄세대, s.lat FROM gold.closed_site s WHERE s.pnu LIKE (SELECT TOP 1 lawd_cd FROM meta.lawd_code WHERE sgg_cd = '11740' AND emd_nm = N'둔촌동' AND ri_nm IS NULL) + '%' ORDER BY s.총괄세대 DESC FOR JSON PATH),
  둔촌표제 = (SELECT TOP 8 t.pnu, t.bld_nm, t.dong_nm, t.shter_day, t.shter_gb_nm, t.regstr_gb_nm FROM silver.bld_closed_title t WHERE t.bld_nm LIKE N'%둔촌%주공%' FOR JSON PATH),
  둔촌표제수 = (SELECT COUNT(*) FROM silver.bld_closed_title t WHERE t.pnu LIKE (SELECT TOP 1 lawd_cd FROM meta.lawd_code WHERE sgg_cd = '11740' AND emd_nm = N'둔촌동' AND ri_nm IS NULL) + '%')
  FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS j;
