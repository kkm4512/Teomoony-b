/* 399_pyeong_price : 평단가(3.3㎡당 매매가) — 단지 × 평형 · 지역 × 종류 × 평형대 (2026-11-01 사장님 "평단가 같은 것도 중요해 · 지역 안에 이런 평형의 실거래가가 이 정도")
   ★ 실거래(원문)로만 계산한 **사실값**이다 — 추정은 여기 없다(2단계 '주변 참고' 는 따로, 표시도 따로).
   ★ 평단가 = 거래금액 ÷ **전용면적** × 3.3058 (원). 분양 광고의 평단가는 보통 **공급면적** 기준이라 이 값보다 낮다 — 화면에 '전용 기준' 이라고 적는다.
     공급면적은 실거래 원문에 없다(우리가 만들지 않는다).
   ★ 넣는 거래: 매매(전월세 아님) · 아파트(APT_TRADE_DEV) · 연립다세대(RH_TRADE) · 오피스텔(OFFI_TRADE) · 전용면적 10㎡ 이상 · 금액 있음.
     빼는 거래: 해제(취소) · 직거래(가족 간 저가 거래가 섞이는 통로) · 지분거래(일부 지분 값) · 분양권/입주권(SILV — 완공 집 값이 아님).
     단독 · 상업용 · 토지는 전용면적이 없어 평단가가 없다(넣지 않는다).
   ★ 값은 **중앙값**(평균은 한두 건에 끌린다) + 하위 25% · 상위 25% + 건수. 건수가 적으면 화면이 그 수를 같이 적는다.
   ★ 기간: 단지 × 평형은 최근 12개월에 거래가 있으면 12개월, 없으면 36개월(기간 칸에 적는다). 지역은 최근 12개월만.
   ★ 지역: 단지의 지금 동네(gold.complex_lawd_now → 없으면 대표 PNU 코드 · 396 확정 대응). 동(법정동 10자리) · 시군구(5자리) 둘 다.
     종류(아파트 · 연립다세대 · 오피스텔)를 **섞지 않는다** — 한 동네에서 아파트와 빌라를 한 중앙값으로 내면 어느 쪽에도 안 맞는다.
     평형대 = 국토부 통계 구간: 60㎡ 이하 · 60~85 · 85~135 · 135 초과(전용). */
SET NOCOUNT ON;
GO
IF OBJECT_ID('gold.complex_pyeong_price') IS NULL
CREATE TABLE gold.complex_pyeong_price (
    complex_id   INT           NOT NULL,
    종류         NVARCHAR(10)  NOT NULL,     -- 아파트 · 연립다세대 · 오피스텔
    평형         INT           NOT NULL,     -- 전용면적 정수 ㎡(FLOOR) — 실거래 탭 평형 칩과 같은 기준
    기간개월     TINYINT       NOT NULL,     -- 12 또는 36
    건수         INT           NOT NULL,
    중앙값       BIGINT        NOT NULL,     -- 원 / 3.3㎡ (전용 기준)
    하위25       BIGINT        NOT NULL,
    상위25       BIGINT        NOT NULL,
    최근계약일   CHAR(8)       NOT NULL,
    최근평단가   BIGINT        NOT NULL,
    기준일       DATE          NOT NULL,
    CONSTRAINT pk_complex_pyeong_price PRIMARY KEY (complex_id, 종류, 평형)
);
GO
IF OBJECT_ID('gold.region_pyeong_price') IS NULL
CREATE TABLE gold.region_pyeong_price (
    지역코드     VARCHAR(10)   NOT NULL,     -- 법정동 10자리 또는 시군구 5자리
    수준         NVARCHAR(4)   NOT NULL,     -- 동 · 시군구
    종류         NVARCHAR(10)  NOT NULL,
    평형대       NVARCHAR(10)  NOT NULL,     -- ~60 · 60~85 · 85~135 · 135~
    단지수       INT           NOT NULL,
    건수         INT           NOT NULL,
    중앙값       BIGINT        NOT NULL,
    하위25       BIGINT        NOT NULL,
    상위25       BIGINT        NOT NULL,
    기준일       DATE          NOT NULL,
    CONSTRAINT pk_region_pyeong_price PRIMARY KEY (지역코드, 종류, 평형대)
);
GO
CREATE OR ALTER PROCEDURE gold.usp_build_pyeong_price AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @오늘 DATE = CAST(DATEADD(HOUR, 9, SYSUTCDATETIME()) AS DATE);   -- 한국 날짜(DB 서버 시계는 UTC)
    DECLARE @d12 CHAR(8) = CONVERT(CHAR(8), DATEADD(MONTH, -12, @오늘), 112), @d36 CHAR(8) = CONVERT(CHAR(8), DATEADD(MONTH, -36, @오늘), 112);

    /* 1 넣을 거래 — 최근 36개월 */
    SELECT t.match_complex_id AS complex_id,
           종류 = CASE t.trade_kind WHEN 'APT_TRADE_DEV' THEN N'아파트' WHEN 'RH_TRADE' THEN N'연립다세대' WHEN 'OFFI_TRADE' THEN N'오피스텔' END,
           평형 = CAST(FLOOR(t.exclu_use_ar) AS INT), 전용 = t.exclu_use_ar, t.deal_ymd,
           평단가 = CAST(ROUND(t.deal_amount / t.exclu_use_ar * 3.3058, 0) AS BIGINT)
      INTO #t
      FROM silver.rtms_trade t
     WHERE t.is_rent = 0 AND t.match_complex_id IS NOT NULL
       AND t.trade_kind IN ('APT_TRADE_DEV', 'RH_TRADE', 'OFFI_TRADE')
       AND t.deal_ymd >= @d36 AND t.deal_amount > 0 AND t.exclu_use_ar >= 10
       AND ISNULL(t.is_canceled, 0) = 0
       AND NOT (t.dealing_gbn LIKE N'%직거래%')
       AND NOT (NULLIF(LTRIM(RTRIM(t.share_dealing)), '') IS NOT NULL AND t.share_dealing NOT LIKE N'%직거래%');
    CREATE CLUSTERED INDEX c ON #t (complex_id, 종류, 평형, deal_ymd);

    /* 2 단지 × 평형: 12개월에 있으면 12, 없으면 36 */
    SELECT complex_id, 종류, 평형, 기간 = CASE WHEN MAX(deal_ymd) >= @d12 THEN 12 ELSE 36 END
      INTO #k FROM #t GROUP BY complex_id, 종류, 평형;
    SELECT t.*, k.기간 INTO #s FROM #t t JOIN #k k ON k.complex_id = t.complex_id AND k.종류 = t.종류 AND k.평형 = t.평형
     WHERE k.기간 = 36 OR t.deal_ymd >= @d12;

    SELECT DISTINCT complex_id, 종류, 평형, 기간,
           건수 = COUNT(*) OVER (PARTITION BY complex_id, 종류, 평형),
           중앙값 = CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY 평단가) OVER (PARTITION BY complex_id, 종류, 평형) AS BIGINT),
           하위25 = CAST(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY 평단가) OVER (PARTITION BY complex_id, 종류, 평형) AS BIGINT),
           상위25 = CAST(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY 평단가) OVER (PARTITION BY complex_id, 종류, 평형) AS BIGINT),
           최근계약일 = FIRST_VALUE(deal_ymd) OVER (PARTITION BY complex_id, 종류, 평형 ORDER BY deal_ymd DESC, 평단가 DESC),
           최근평단가 = FIRST_VALUE(평단가) OVER (PARTITION BY complex_id, 종류, 평형 ORDER BY deal_ymd DESC, 평단가 DESC)
      INTO #c FROM #s;

    /* 3 지역 × 종류 × 평형대 — 최근 12개월. 지역 = 단지의 지금 동네 */
    SELECT t.*, 동 = CAST(COALESCE(nw.지금코드, s.새코드, LEFT(c.rep_pnu, 10)) AS VARCHAR(10)),
           평형대 = CASE WHEN t.전용 <= 60 THEN N'~60' WHEN t.전용 <= 85 THEN N'60~85' WHEN t.전용 <= 135 THEN N'85~135' ELSE N'135~' END
      INTO #r
      FROM #t t
      JOIN gold.complex c ON c.complex_id = t.complex_id AND c.merged_into IS NULL
      LEFT JOIN gold.complex_lawd_now nw ON nw.complex_id = t.complex_id
      LEFT JOIN gold.bdong_succ_code s ON s.옛코드 = LEFT(c.rep_pnu, 10)
     WHERE t.deal_ymd >= @d12 AND LEN(c.rep_pnu) = 19;

    SELECT 지역코드, 수준, 종류, 평형대, 단지수 = COUNT(DISTINCT complex_id), 건수 = COUNT(*),
           중앙값 = MAX(m50), 하위25 = MAX(m25), 상위25 = MAX(m75)
      INTO #g
      FROM (SELECT 지역코드 = 동, 수준 = N'동', 종류, 평형대, complex_id,
                   m50 = CAST(PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY 평단가) OVER (PARTITION BY 동, 종류, 평형대) AS BIGINT),
                   m25 = CAST(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY 평단가) OVER (PARTITION BY 동, 종류, 평형대) AS BIGINT),
                   m75 = CAST(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY 평단가) OVER (PARTITION BY 동, 종류, 평형대) AS BIGINT)
              FROM #r
            UNION ALL
            SELECT LEFT(동, 5), N'시군구', 종류, 평형대, complex_id,
                   CAST(PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY 평단가) OVER (PARTITION BY LEFT(동, 5), 종류, 평형대) AS BIGINT),
                   CAST(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY 평단가) OVER (PARTITION BY LEFT(동, 5), 종류, 평형대) AS BIGINT),
                   CAST(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY 평단가) OVER (PARTITION BY LEFT(동, 5), 종류, 평형대) AS BIGINT)
              FROM #r) z
     GROUP BY 지역코드, 수준, 종류, 평형대;

    BEGIN TRAN;
    DELETE FROM gold.complex_pyeong_price;
    INSERT gold.complex_pyeong_price (complex_id, 종류, 평형, 기간개월, 건수, 중앙값, 하위25, 상위25, 최근계약일, 최근평단가, 기준일)
    SELECT complex_id, 종류, 평형, 기간, 건수, 중앙값, 하위25, 상위25, 최근계약일, 최근평단가, @오늘 FROM #c;
    DELETE FROM gold.region_pyeong_price;
    INSERT gold.region_pyeong_price (지역코드, 수준, 종류, 평형대, 단지수, 건수, 중앙값, 하위25, 상위25, 기준일)
    SELECT 지역코드, 수준, 종류, 평형대, 단지수, 건수, 중앙값, 하위25, 상위25, @오늘 FROM #g;
    COMMIT;
    SELECT 단지평형 = (SELECT COUNT(*) FROM gold.complex_pyeong_price), 단지 = (SELECT COUNT(DISTINCT complex_id) FROM gold.complex_pyeong_price),
           지역줄 = (SELECT COUNT(*) FROM gold.region_pyeong_price), 거래 = (SELECT COUNT(*) FROM #t), 기준일 = @오늘;
END
GO
