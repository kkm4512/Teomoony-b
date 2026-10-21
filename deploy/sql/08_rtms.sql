SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* ============================================================
   08_rtms : 국토교통부 실거래가 (매매 + 전월세, 11종)

   ★ 이 축만 키가 없다. 그리고 종목마다 매칭 가능성이 다르다.

   ┌─────────────────────┬──────────────┬──────────────────┐
   │ 종목                │ 지번          │ PNU 매칭         │
   ├─────────────────────┼──────────────┼──────────────────┤
   │ 아파트 매매 상세      │ 코드 제공     │ 직접 조립  ★최선  │
   │ 아파트 매매(구)       │ 204-11       │ 이름->코드 경유   │
   │ 아파트 전월세         │ 211          │ 이름->코드 경유   │
   │ 연립다세대 매매/전월세 │ 70-13        │ 이름->코드 경유   │
   │ 오피스텔 매매/전월세   │ 73           │ 이름->코드 경유   │
   │ 단독다가구 매매       │ 1**  마스킹   │ 불가             │
   │ 단독다가구 전월세      │ 없음          │ 불가             │
   │ 토지 매매            │ 1**  마스킹   │ 불가             │
   │ 상업업무용 매매       │ 1**  마스킹   │ 불가             │
   └─────────────────────┴──────────────┴──────────────────┘

   개인 식별을 막으려고 단독주택/토지/상업용은 지번 뒷자리를 가린다.
   이 네 종목은 법정동 단위 집계까지만 가능하다. 설계로 못 푼다.

   ★ 아파트는 반드시 '상세(AptTradeDev)' 를 쓴다.
     sggCd + umdCd + landCd + bonbun + bubun 로 PNU 가 바로 나오고,
     roadNmSggCd + roadNmCd 로 도로명코드 12자리도 나온다.
     구 엔드포인트는 법정동 "이름" 만 줘서 meta.lawd_code 를 거쳐야 한다.

   ★ API 가 거래 고유번호를 주지 않는다. 자연키 해시로 중복을 막는다.
   ★ 해제 거래(cdealType='O')는 같은 거래가 다시 내려온다.
     자연키에서 해제 필드를 빼고 기존 행을 UPDATE 한다.
   ============================================================ */
USE Teomoony;
GO

IF OBJECT_ID('silver.rtms_trade') IS NOT NULL DROP TABLE silver.rtms_trade;
GO
CREATE TABLE silver.rtms_trade (
    trade_sk        BIGINT IDENTITY(1,1) NOT NULL,
    nat_key         BINARY(32)     NOT NULL,   -- 자연키 (API 가 PK 를 안 준다)
    trade_kind      VARCHAR(20)    NOT NULL,   -- APT_TRADE_DEV | RH_TRADE | SH_RENT ...
    is_rent         BIT            NOT NULL DEFAULT 0,
    /* 주소 요소 */
    sgg_cd          CHAR(5)        NULL,
    umd_cd          CHAR(5)        NULL,       -- 상세 자료만 제공
    umd_nm          NVARCHAR(40)   NULL,
    land_cd         VARCHAR(2)     NULL,       -- 1 일반 / 2 산
    bonbun          VARCHAR(10)    NULL,
    bubun           VARCHAR(10)    NULL,
    jibun           NVARCHAR(40)   NULL,       -- '1**' 처럼 마스킹될 수 있다
    jibun_masked    BIT            NOT NULL DEFAULT 0,
    /* 도로명 (일부 종목만) */
    road_nm         NVARCHAR(80)   NULL,
    road_cd         CHAR(12)       NULL,       -- roadNmSggCd + roadNmCd
    road_bonbun     VARCHAR(10)    NULL,
    road_bubun      VARCHAR(10)    NULL,
    /* 대상 */
    bld_nm          NVARCHAR(200)  NULL,       -- aptNm / mhouseNm / offiNm
    bld_dong        NVARCHAR(40)   NULL,
    house_type      NVARCHAR(40)   NULL,       -- 단독 / 다가구 / 연립 / 다세대
    building_use    NVARCHAR(80)   NULL,
    building_type   NVARCHAR(80)   NULL,
    land_use        NVARCHAR(80)   NULL,
    jimok           NVARCHAR(40)   NULL,
    apt_seq         NVARCHAR(40)   NULL,
    /* 거래 */
    deal_ymd        CHAR(8)        NULL,
    deal_year       INT            NULL,
    deal_month      INT            NULL,
    deal_amount     BIGINT         NULL,       -- 매매가 (원)
    deposit         BIGINT         NULL,       -- 보증금 (원)
    monthly_rent    BIGINT         NULL,       -- 월세 (원)
    pre_deposit     BIGINT         NULL,
    pre_monthly_rent BIGINT        NULL,
    contract_term   NVARCHAR(40)   NULL,
    contract_type   NVARCHAR(40)   NULL,
    use_rr_right    NVARCHAR(10)   NULL,       -- 갱신요구권 사용
    /* 면적 */
    exclu_use_ar    DECIMAL(12,4)  NULL,       -- 전용면적
    total_floor_ar  DECIMAL(12,4)  NULL,       -- 연면적
    plottage_ar     DECIMAL(12,4)  NULL,       -- 대지면적
    building_ar     DECIMAL(12,4)  NULL,       -- 건물면적
    land_ar         DECIMAL(12,4)  NULL,
    deal_area       DECIMAL(12,4)  NULL,       -- 토지 거래면적
    floor_no        INT            NULL,
    build_year      INT            NULL,
    /* 기타 */
    dealing_gbn     NVARCHAR(40)   NULL,
    buyer_gbn       NVARCHAR(40)   NULL,
    sler_gbn        NVARCHAR(40)   NULL,
    share_dealing   NVARCHAR(40)   NULL,
    estate_agent_sgg NVARCHAR(80)  NULL,
    land_leasehold  VARCHAR(4)     NULL,
    rgst_date       NVARCHAR(20)   NULL,
    /* 해제 */
    cdeal_type      VARCHAR(4)     NULL,
    cdeal_day       NVARCHAR(20)   NULL,
    is_canceled     AS (CASE WHEN cdeal_type = 'O' THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END) PERSISTED,
    /* 매칭 */
    match_pnu        CHAR(19)      NULL,
    match_complex_id INT           NULL,
    match_method     VARCHAR(24)   NULL,
        /* CODE_DIRECT : 상세 자료의 코드로 바로 조립 (가장 신뢰)
           LAWD_JIBUN  : 법정동 이름 -> 코드 -> 지번 파싱
           MASKED      : 지번이 가려져 조립 불가
           NO_LAWD     : 법정동 코드를 못 찾음
           NONE        : 기타 실패                            */
    match_note       NVARCHAR(200) NULL,
    src_run_id      BIGINT         NULL,
    loaded_at       DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_rtms_trade PRIMARY KEY CLUSTERED (trade_sk)
);
GO
CREATE UNIQUE INDEX uq_rtms_natkey  ON silver.rtms_trade (nat_key);
CREATE INDEX ix_rtms_complex ON silver.rtms_trade (match_complex_id, deal_ymd DESC)
    INCLUDE (deal_amount, deposit, monthly_rent, exclu_use_ar, floor_no, bld_nm, trade_kind, is_rent);
CREATE INDEX ix_rtms_pnu   ON silver.rtms_trade (match_pnu);
CREATE INDEX ix_rtms_scope ON silver.rtms_trade (sgg_cd, umd_nm, deal_ymd);
GO

/* ============================================================
   단지별 실거래 요약 (해제 제외, 매매만)
   ============================================================ */
IF COL_LENGTH('gold.complex','trade_cnt') IS NULL
ALTER TABLE gold.complex ADD
    trade_cnt      INT            NULL,
    rent_cnt       INT            NULL,
    trade_last_ymd CHAR(8)        NULL,
    trade_last_amt BIGINT         NULL,
    trade_avg_unit DECIMAL(19,2)  NULL;
GO

IF OBJECT_ID('gold.usp_refresh_complex_trade') IS NOT NULL
    DROP PROCEDURE gold.usp_refresh_complex_trade;
GO
CREATE PROCEDURE gold.usp_refresh_complex_trade
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE gold.complex SET trade_cnt=NULL, rent_cnt=NULL,
           trade_last_ymd=NULL, trade_last_amt=NULL, trade_avg_unit=NULL;

    WITH t AS (
        SELECT match_complex_id AS cid,
               SUM(CASE WHEN is_rent=0 THEN 1 ELSE 0 END) AS tcnt,
               SUM(CASE WHEN is_rent=1 THEN 1 ELSE 0 END) AS rcnt,
               MAX(CASE WHEN is_rent=0 THEN deal_ymd END) AS last_ymd,
               AVG(CASE WHEN is_rent=0 AND exclu_use_ar > 0
                        THEN deal_amount / exclu_use_ar END)   AS unit
        FROM silver.rtms_trade
        WHERE match_complex_id IS NOT NULL AND is_canceled = 0
        GROUP BY match_complex_id
    )
    UPDATE c SET c.trade_cnt=t.tcnt, c.rent_cnt=t.rcnt,
                 c.trade_last_ymd=t.last_ymd, c.trade_avg_unit=t.unit,
                 c.updated_at=SYSDATETIME()
      FROM gold.complex c JOIN t ON t.cid = c.complex_id;

    WITH last1 AS (
        SELECT match_complex_id AS cid, deal_amount,
               ROW_NUMBER() OVER (PARTITION BY match_complex_id
                                  ORDER BY deal_ymd DESC, deal_amount DESC) rn
        FROM silver.rtms_trade
        WHERE match_complex_id IS NOT NULL AND is_canceled = 0 AND is_rent = 0
    )
    UPDATE c SET c.trade_last_amt = l.deal_amount
      FROM gold.complex c JOIN last1 l ON l.cid=c.complex_id AND l.rn=1;
END
GO

/* 매칭 품질 모니터링 */
IF OBJECT_ID('gold.v_rtms_match_quality') IS NOT NULL DROP VIEW gold.v_rtms_match_quality;
GO
CREATE VIEW gold.v_rtms_match_quality
AS
SELECT trade_kind, match_method,
       COUNT(*)                                                     AS cnt,
       SUM(CASE WHEN match_pnu IS NOT NULL THEN 1 ELSE 0 END)        AS pnu_ok,
       SUM(CASE WHEN match_complex_id IS NOT NULL THEN 1 ELSE 0 END) AS complex_ok,
       SUM(CASE WHEN is_canceled = 1 THEN 1 ELSE 0 END)              AS canceled
FROM silver.rtms_trade
GROUP BY trade_kind, match_method;
GO

/* 프론트 뷰 */
IF OBJECT_ID('gold.v_complex_map') IS NOT NULL DROP VIEW gold.v_complex_map;
GO
CREATE VIEW gold.v_complex_map
AS
SELECT
    c.complex_id, c.complex_nm, c.grouping_rule, c.has_recap,
    c.sigungu_cd, c.bjdong_cd, l.full_nm AS lawd_nm,
    c.rep_pnu, meta.fn_pnu_to_jibun(c.rep_pnu) AS rep_jibun,
    c.rep_plat_plc, c.rep_road_addr,
    c.dong_cnt, c.bld_cnt, c.max_floor,
    c.pnu_cnt, c.parcel_hit,
    c.hhld_cnt_sum, c.tot_area_sum,
    c.oldest_use_apr, c.latest_use_apr, c.jiga_avg,
    c.trade_cnt, c.rent_cnt, c.trade_last_ymd, c.trade_last_amt, c.trade_avg_unit,
    c.centroid_lat, c.centroid_lng,
    c.bbox_minx, c.bbox_miny, c.bbox_maxx, c.bbox_maxy
FROM gold.complex c
LEFT JOIN meta.lawd_code l ON l.lawd_cd = LEFT(c.rep_pnu,10);
GO

PRINT '08_rtms done.';
GO
