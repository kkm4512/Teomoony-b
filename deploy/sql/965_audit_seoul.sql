/* 965_audit_seoul — 서울 빠진 데이터 · 매칭 빈칸 점검 (2026-10-23 사장님 "서울 먼저 완벽하게 · 1,2번 ㄱㄱ"). 읽기만 한다. */
SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* 1 건축물대장 op × 구: 지금 있는(폐지 아닌) 법정동 기준 */
SELECT (SELECT p.sgg_cd, p.op_alias, 동 = COUNT(*),
               완료 = SUM(CASE WHEN p.상태 = 'DONE' THEN 1 ELSE 0 END),
               재시도 = SUM(CASE WHEN p.상태 = 'RETRY' THEN 1 ELSE 0 END),
               남음 = SUM(CASE WHEN p.상태 = 'TODO' THEN 1 ELSE 0 END)
          FROM meta.v_load_plan p JOIN meta.lawd_code l ON l.lawd_cd = p.lawd_cd
         WHERE p.sgg_cd LIKE '11%' AND l.is_abolished = 0 AND l.ri_nm IS NULL AND l.emd_nm IS NOT NULL
         GROUP BY p.sgg_cd, p.op_alias FOR JSON PATH) AS j;
GO
SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* 2 구마다 법정동 수 · 대상(load_target) 여부 · 폐쇄 표제부/상세 받은 동 · 도로명주소 받은 동 · 필지 · 좌표 없는 단지 */
WITH d AS (SELECT l.sgg_cd, l.sgg_nm, 동 = COUNT(*) FROM meta.lawd_code l
            WHERE l.sido_cd = '11' AND l.is_abolished = 0 AND l.ri_nm IS NULL AND l.emd_nm IS NOT NULL GROUP BY l.sgg_cd, l.sgg_nm),
ct AS (SELECT sgg = LEFT(pnu, 5), 동 = COUNT(DISTINCT LEFT(pnu, 10)), 행 = COUNT(*) FROM silver.bld_closed_title WHERE pnu LIKE '11%' GROUP BY LEFT(pnu, 5)),
cd AS (SELECT sgg = LEFT(pnu, 5), 동 = COUNT(DISTINCT LEFT(pnu, 10)), 필지 = COUNT(DISTINCT pnu) FROM silver.bld_closed_detail_done WHERE pnu LIKE '11%' GROUP BY LEFT(pnu, 5)),
cs AS (SELECT sgg = LEFT(pnu, 5), 자리 = COUNT(*), 좌표없음 = SUM(CASE WHEN lat IS NULL THEN 1 ELSE 0 END), 이름있음 = SUM(CASE WHEN 이름 IS NOT NULL THEN 1 ELSE 0 END) FROM gold.closed_site WHERE pnu LIKE '11%' GROUP BY LEFT(pnu, 5)),
ja AS (SELECT sgg = LEFT(lawd_cd, 5), 동 = COUNT(DISTINCT lawd_cd), 다 = SUM(CASE WHEN 다받음 = 1 THEN 1 ELSE 0 END) FROM silver.juso_addr_done WHERE lawd_cd LIKE '11%' GROUP BY LEFT(lawd_cd, 5)),
cp AS (SELECT sgg = LEFT(pnu, 5), 필지 = COUNT(*) FROM silver.cadastral_parcel WHERE is_current = 1 AND pnu LIKE '11%' GROUP BY LEFT(pnu, 5)),
cx AS (SELECT sgg = sigungu_cd, 단지 = COUNT(*), 세대단지 = SUM(CASE WHEN hhld_cnt_sum > 0 THEN 1 ELSE 0 END),
              좌표없음 = SUM(CASE WHEN centroid_lat IS NULL THEN 1 ELSE 0 END), 세대좌표없음 = SUM(CASE WHEN centroid_lat IS NULL AND hhld_cnt_sum > 0 THEN 1 ELSE 0 END),
              주소이름 = SUM(CASE WHEN complex_nm_src = 'ADDR' THEN 1 ELSE 0 END)
         FROM gold.complex WHERE is_active = 1 AND sigungu_cd LIKE '11%' GROUP BY sigungu_cd),
lt AS (SELECT sgg_cd, 대상 = MAX(CASE WHEN bjdong_cd IS NULL THEN '구 전체' ELSE '일부 동' END), ops = MAX(ops) FROM meta.load_target WHERE enabled = 1 GROUP BY sgg_cd)
SELECT (SELECT d.sgg_cd, d.sgg_nm, 법정동 = d.동, 대상 = lt.대상, lt.ops,
               폐쇄표제동 = ct.동, 폐쇄표제행 = ct.행, 폐쇄상세동 = cd.동, 폐쇄상세필지 = cd.필지, 폐쇄자리 = cs.자리, 폐쇄좌표없음 = cs.좌표없음, 폐쇄이름 = cs.이름있음,
               도로명동 = ja.동, 도로명다받음 = ja.다, 필지 = cp.필지,
               cx.단지, cx.세대단지, cx.좌표없음, cx.세대좌표없음, cx.주소이름
          FROM d LEFT JOIN ct ON ct.sgg = d.sgg_cd LEFT JOIN cd ON cd.sgg = d.sgg_cd LEFT JOIN cs ON cs.sgg = d.sgg_cd
          LEFT JOIN ja ON ja.sgg = d.sgg_cd LEFT JOIN cp ON cp.sgg = d.sgg_cd LEFT JOIN cx ON cx.sgg = d.sgg_cd LEFT JOIN lt ON lt.sgg_cd = d.sgg_cd
         ORDER BY d.sgg_cd FOR JSON PATH) AS j;
GO
SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* 3 실거래 구 × 종목: 받은 달 범위 · 빈 달 · 붙은 비율 */
WITH m AS (SELECT sgg_cd, trade_kind, ym = deal_year * 100 + deal_month, n = COUNT(*),
                  붙음 = SUM(CASE WHEN match_complex_id IS NOT NULL THEN 1 ELSE 0 END),
                  가림 = SUM(CASE WHEN jibun_masked = 1 THEN 1 ELSE 0 END)
             FROM silver.rtms_trade WHERE sgg_cd LIKE '11%' GROUP BY sgg_cd, trade_kind, deal_year, deal_month)
SELECT (SELECT sgg_cd, trade_kind, 처음 = MIN(ym), 끝 = MAX(ym), 달 = COUNT(*),
               기대달 = (MAX(ym) / 100 - MIN(ym) / 100) * 12 + MAX(ym) % 100 - MIN(ym) % 100 + 1,
               행 = SUM(n), 붙음 = SUM(붙음), 가림 = SUM(가림)
          FROM m GROUP BY sgg_cd, trade_kind ORDER BY sgg_cd, trade_kind FOR JSON PATH) AS j;
GO
SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* 4 실거래 안 붙은 까닭(서울) — 종목 × 매칭 방법 × 지번 가림 × 필지 찾음 */
SELECT (SELECT TOP 80 trade_kind, 방법 = ISNULL(match_method, '-'), 가림 = jibun_masked, 필지찾음 = CASE WHEN match_pnu IS NULL THEN 0 ELSE 1 END,
               붙음 = CASE WHEN match_complex_id IS NULL THEN 0 ELSE 1 END, 행 = COUNT(*)
          FROM silver.rtms_trade WHERE sgg_cd LIKE '11%'
         GROUP BY trade_kind, ISNULL(match_method, '-'), jibun_masked, CASE WHEN match_pnu IS NULL THEN 0 ELSE 1 END, CASE WHEN match_complex_id IS NULL THEN 0 ELSE 1 END
         ORDER BY trade_kind, COUNT(*) DESC FOR JSON PATH) AS j;
GO
SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* 5 안 붙은 실거래의 match_note 상위(서울 · 지번 안 가린 것) */
SELECT (SELECT TOP 60 trade_kind, note = LEFT(ISNULL(match_note, '-'), 80), 행 = COUNT(*)
          FROM silver.rtms_trade WHERE sgg_cd LIKE '11%' AND match_complex_id IS NULL AND ISNULL(jibun_masked, 0) = 0
         GROUP BY trade_kind, LEFT(ISNULL(match_note, '-'), 80) ORDER BY COUNT(*) DESC FOR JSON PATH) AS j;
GO
SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* 6 K-apt · 청약 · 공시가격 · 토지 칸 · 인허가 (서울) */
WITH kc AS (SELECT k.kapt_code, k.bjd_code, k.pnu, k.hhld_cnt, k.kapt_usedate, k.code_sale_nm FROM silver.kapt_complex k WHERE k.is_current = 1 AND k.bjd_code LIKE '11%'),
kl AS (SELECT DISTINCT kapt_code FROM gold.complex_kapt),
ah AS (SELECT p.house_manage_no, p.공고종류, p.lawd_cd, p.pnu FROM silver.applyhome_pblanc p WHERE p.lawd_cd LIKE '11%' OR p.hssply_adres LIKE N'서울%'),
ahl AS (SELECT DISTINCT house_manage_no FROM gold.applyhome_link),
cpn AS (SELECT DISTINCT cp.pnu FROM gold.complex_pnu cp JOIN gold.complex c ON c.complex_id = cp.complex_id WHERE c.is_active = 1 AND c.hhld_cnt_sum > 0 AND cp.pnu LIKE '11%'),
par AS (SELECT pnu FROM silver.cadastral_parcel WHERE is_current = 1 AND pnu LIKE '11%')
SELECT (SELECT
  kapt서울 = (SELECT COUNT(*) FROM kc), kapt이음 = (SELECT COUNT(*) FROM kc WHERE kapt_code IN (SELECT kapt_code FROM kl)),
  kapt안이음_필지없음 = (SELECT COUNT(*) FROM kc WHERE kapt_code NOT IN (SELECT kapt_code FROM kl) AND pnu IS NULL),
  청약서울 = (SELECT COUNT(DISTINCT house_manage_no) FROM ah), 청약이음 = (SELECT COUNT(DISTINCT house_manage_no) FROM ah WHERE house_manage_no IN (SELECT house_manage_no FROM ahl)),
  청약종류 = (SELECT 공고종류, 전체 = COUNT(DISTINCT house_manage_no), 이음 = COUNT(DISTINCT CASE WHEN house_manage_no IN (SELECT house_manage_no FROM ahl) THEN house_manage_no END)
               FROM ah GROUP BY 공고종류 FOR JSON PATH),
  세대단지필지 = (SELECT COUNT(*) FROM cpn), 공시받음 = (SELECT COUNT(*) FROM cpn WHERE pnu IN (SELECT pnu FROM silver.ned_aphus_done)),
  공시값있음 = (SELECT COUNT(*) FROM cpn WHERE pnu IN (SELECT pnu FROM silver.ned_aphus_done WHERE 건수 > 0)),
  필지 = (SELECT COUNT(*) FROM par),
  토지이용받음 = (SELECT COUNT(*) FROM par WHERE pnu IN (SELECT pnu FROM silver.land_use_done)),
  토지이동받음 = (SELECT COUNT(*) FROM par WHERE pnu IN (SELECT pnu FROM silver.land_move_done)),
  토지특성있음 = (SELECT COUNT(*) FROM par WHERE pnu IN (SELECT pnu FROM silver.land_char WHERE is_current = 1)),
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
