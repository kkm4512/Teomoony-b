/* 345 잇기 성공률 재기 — ops.match_rate 에 남는다. 다시 재려면 이 파일을 다시 돌린다 */
/* 2026-10-24 사장님 "서울 기준으로 만든 매칭 규칙이 어느 정도 맞았나 — 70% 이하면 규칙을 더 만들어야" — 잇기별 성공률 · 서울 vs 안양(서울 밖 첫 지역) */
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @r TABLE (잇기 NVARCHAR(60), 지역 NVARCHAR(10), 분모 BIGINT, 이음 BIGINT, 비고 NVARCHAR(200));

/* ① 실거래 → 단지 (지번이 가려진 단독·토지·상업, 일부러 안 잇는 분양권은 뺌) — 전체 / 2020년 이후 */
INSERT @r
SELECT N'실거래→단지 ' + g, 지역, COUNT_BIG(*), SUM(CASE WHEN match_complex_id IS NOT NULL THEN 1 ELSE 0 END), N'전 기간'
  FROM (SELECT g = CASE WHEN trade_kind LIKE 'APT_TRADE%' THEN N'아파트 매매' WHEN trade_kind = 'APT_RENT' THEN N'아파트 전월세'
                        WHEN trade_kind LIKE 'OFFI%' THEN N'오피스텔' WHEN trade_kind LIKE 'RH%' THEN N'연립·다세대' END,
               지역 = CASE WHEN sgg_cd LIKE '11%' THEN N'서울' WHEN sgg_cd LIKE '4117%' THEN N'안양' ELSE N'그외' END, match_complex_id
          FROM silver.rtms_trade WHERE trade_kind LIKE 'APT%' OR trade_kind LIKE 'OFFI%' OR trade_kind LIKE 'RH%') x
 GROUP BY g, 지역;
INSERT @r
SELECT N'실거래→단지 ' + g, 지역, COUNT_BIG(*), SUM(CASE WHEN match_complex_id IS NOT NULL THEN 1 ELSE 0 END), N'2020년 이후'
  FROM (SELECT g = CASE WHEN trade_kind LIKE 'APT_TRADE%' THEN N'아파트 매매' WHEN trade_kind = 'APT_RENT' THEN N'아파트 전월세'
                        WHEN trade_kind LIKE 'OFFI%' THEN N'오피스텔' WHEN trade_kind LIKE 'RH%' THEN N'연립·다세대' END,
               지역 = CASE WHEN sgg_cd LIKE '11%' THEN N'서울' WHEN sgg_cd LIKE '4117%' THEN N'안양' ELSE N'그외' END, match_complex_id
          FROM silver.rtms_trade WHERE (trade_kind LIKE 'APT%' OR trade_kind LIKE 'OFFI%' OR trade_kind LIKE 'RH%') AND deal_ymd >= '20200101') x
 GROUP BY g, 지역;
/* 실거래 → 필지(PNU) */
INSERT @r
SELECT N'실거래→필지(PNU) 지번 공개 종목', 지역, COUNT_BIG(*), SUM(CASE WHEN match_pnu IS NOT NULL THEN 1 ELSE 0 END), N'전 기간'
  FROM (SELECT 지역 = CASE WHEN sgg_cd LIKE '11%' THEN N'서울' WHEN sgg_cd LIKE '4117%' THEN N'안양' ELSE N'그외' END, match_pnu
          FROM silver.rtms_trade WHERE trade_kind LIKE 'APT%' OR trade_kind LIKE 'OFFI%' OR trade_kind LIKE 'RH%') x GROUP BY 지역;

/* ② K-apt 단지 → 우리 단지 */
INSERT @r
SELECT N'K-apt→단지', 지역, COUNT(*), SUM(ok), N'K-apt 지금 단지'
  FROM (SELECT *, ok = CASE WHEN EXISTS (SELECT 1 FROM gold.complex_kapt ck WHERE ck.kapt_code = k.kapt_code) THEN 1 ELSE 0 END FROM (SELECT kapt_code, 지역 = CASE WHEN bjd_code LIKE '11%' THEN N'서울' WHEN bjd_code LIKE '4117%' THEN N'안양' ELSE N'그외' END
          FROM silver.kapt_complex WHERE is_current = 1) k) k1 GROUP BY 지역;
/* 우리 큰 단지(주택 300세대 이상 · 의무 공개 대상) → K-apt */
INSERT @r
SELECT N'단지(300세대↑)→K-apt', 지역, COUNT(*), SUM(ok), N'공동주택관리법 의무 공개 규모'
  FROM (SELECT *, ok = CASE WHEN EXISTS (SELECT 1 FROM gold.complex_kapt ck WHERE ck.complex_id = c.complex_id) THEN 1 ELSE 0 END FROM (SELECT complex_id, 지역 = CASE WHEN sigungu_cd LIKE '11%' THEN N'서울' WHEN sigungu_cd LIKE '4117%' THEN N'안양' ELSE N'그외' END
          FROM gold.complex WHERE is_active = 1 AND merged_into IS NULL AND hhld_cnt_sum >= 300) c) c1 GROUP BY 지역;

/* ③ 청약 공고 → 단지 (입주예정월이 지난 공고 = 지금 지어져 있어야 하는 것) */
INSERT @r
SELECT N'청약공고→단지(입주 지난 것)', 지역, COUNT(*), SUM(ok), N'입주예정월 ≤ 2026.09'
  FROM (SELECT *, ok = CASE WHEN EXISTS (SELECT 1 FROM gold.applyhome_link l WHERE l.house_manage_no = p.house_manage_no AND (l.complex_id IS NOT NULL OR l.kapt_code IS NOT NULL)) THEN 1 ELSE 0 END FROM (SELECT DISTINCT house_manage_no, 지역 = CASE WHEN lawd_cd LIKE '11%' THEN N'서울' WHEN lawd_cd LIKE '4117%' THEN N'안양' ELSE N'그외' END
          FROM silver.applyhome_pblanc WHERE mvn_prearnge_ym <= '202609') p) p1 GROUP BY 지역;
INSERT @r
SELECT N'청약공고→필지(PNU)', 지역, COUNT(*), SUM(CASE WHEN pnu IS NOT NULL THEN 1 ELSE 0 END), N'공고 주소 → 지번'
  FROM (SELECT house_manage_no, pnu = MAX(pnu), 지역 = MAX(CASE WHEN lawd_cd LIKE '11%' THEN N'서울' WHEN lawd_cd LIKE '4117%' THEN N'안양' ELSE N'그외' END)
          FROM silver.applyhome_pblanc GROUP BY house_manage_no) p GROUP BY 지역;

/* ④ 학교알리미 → 학교 위치 */
INSERT @r
SELECT N'학교알리미→학교위치', 지역, COUNT(*), SUM(ok), N'초·중·고'
  FROM (SELECT *, ok = CASE WHEN EXISTS (SELECT 1 FROM gold.school_link l WHERE l.schul_code = i.schul_code) THEN 1 ELSE 0 END FROM (SELECT schul_code, 지역 = CASE WHEN adrcd_cd LIKE '11%' THEN N'서울' WHEN adrcd_cd LIKE '4117%' THEN N'안양' ELSE N'그외' END FROM silver.schoolinfo) i) i1 GROUP BY 지역;

/* ⑤ 공동주택가격(NED) → 호 — 최근 연도 */
INSERT @r
SELECT N'공동주택가격(NED)→호', 지역, COUNT_BIG(*), SUM(CASE WHEN l.호PK IS NOT NULL THEN 1 ELSE 0 END), N'최근 기준연도 · 동·호 단위'
  FROM (SELECT DISTINCT n.pnu, n.공동주택코드, n.동명, n.호명, 지역 = CASE WHEN n.pnu LIKE '11%' THEN N'서울' WHEN n.pnu LIKE '4117%' THEN N'안양' ELSE N'그외' END
          FROM silver.ned_aphus_price n WHERE n.기준연도 = (SELECT MAX(기준연도) FROM silver.ned_aphus_price)) x
  OUTER APPLY (SELECT TOP 1 h.호PK FROM gold.ned_ho_link h WHERE h.pnu = x.pnu AND h.공동주택코드 = x.공동주택코드 AND h.동명 = x.동명 AND h.호명 = x.호명) l
 GROUP BY 지역;

/* ⑥ 단지 바탕 — 필지 · 좌표 · 도로명 */
INSERT @r
SELECT N'주거단지→좌표', 지역, COUNT(*), SUM(CASE WHEN centroid_lat IS NOT NULL THEN 1 ELSE 0 END), N'세대 있는 단지'
  FROM (SELECT centroid_lat, 지역 = CASE WHEN sigungu_cd LIKE '11%' THEN N'서울' WHEN sigungu_cd LIKE '4117%' THEN N'안양' ELSE N'그외' END
          FROM gold.complex WHERE is_active = 1 AND merged_into IS NULL AND hhld_cnt_sum > 0) c GROUP BY 지역;
INSERT @r
SELECT N'주거단지→필지(연속지적)', 지역, COUNT(*), SUM(CASE WHEN parcel_hit > 0 THEN 1 ELSE 0 END), N'세대 있는 단지 · 대표 필지가 지적도에 있음'
  FROM (SELECT parcel_hit, 지역 = CASE WHEN sigungu_cd LIKE '11%' THEN N'서울' WHEN sigungu_cd LIKE '4117%' THEN N'안양' ELSE N'그외' END
          FROM gold.complex WHERE is_active = 1 AND merged_into IS NULL AND hhld_cnt_sum > 0) c GROUP BY 지역;
INSERT @r
SELECT N'주거단지→실거래 이름(별칭)', 지역, COUNT(*), SUM(ok), N'세대 있는 단지 · 거래가 붙은 단지만'
  FROM (SELECT *, ok = CASE WHEN EXISTS (SELECT 1 FROM gold.complex_alias a WHERE a.complex_id = c.complex_id) THEN 1 ELSE 0 END FROM (SELECT complex_id, 지역 = CASE WHEN sigungu_cd LIKE '11%' THEN N'서울' WHEN sigungu_cd LIKE '4117%' THEN N'안양' ELSE N'그외' END
          FROM gold.complex WHERE is_active = 1 AND merged_into IS NULL AND hhld_cnt_sum > 0 AND trade_cnt > 0) c) c1 GROUP BY 지역;

/* ⑦ 폐쇄·말소 대장 → 좌표 · 지금 단지 */
INSERT @r
SELECT N'폐쇄대장 터→좌표', 지역, COUNT(*), SUM(CASE WHEN lat IS NOT NULL THEN 1 ELSE 0 END), N''
  FROM (SELECT lat, 지역 = CASE WHEN pnu LIKE '11%' THEN N'서울' WHEN pnu LIKE '4117%' THEN N'안양' ELSE N'그외' END FROM gold.closed_site) s GROUP BY 지역;

/* ⑧ 정비계획(서울) → 정비구역 */
INSERT @r SELECT N'정비계획→정비구역', N'서울', (SELECT COUNT(*) FROM silver.seoul_redev_plan), (SELECT COUNT(DISTINCT basic_info_seq) FROM gold.redev_plan_link), N'서울 열린데이터';

/* 결과는 기록표에 남긴다(sqlcmd 가 긴 JSON 을 자른다 · 다음에 다시 재면 나란히 견준다) */
IF OBJECT_ID('ops.match_rate') IS NULL
    CREATE TABLE ops.match_rate (잰때 DATETIME2(0) NOT NULL, 잇기 NVARCHAR(60) NOT NULL, 지역 NVARCHAR(10) NOT NULL, 분모 BIGINT, 이음 BIGINT, 율 DECIMAL(5,1), 비고 NVARCHAR(200));
DECLARE @t DATETIME2(0) = SYSDATETIME();
INSERT ops.match_rate SELECT @t, 잇기, 지역, 분모, 이음, CAST(100.0 * 이음 / NULLIF(분모, 0) AS DECIMAL(5,1)), 비고 FROM @r WHERE 지역 <> N'그외' OR 분모 > 50;
SELECT 잰때 = @t, 줄 = @@ROWCOUNT;
