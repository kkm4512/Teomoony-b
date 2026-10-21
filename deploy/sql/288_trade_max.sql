/* ============================================================
   288_trade_max : 단지마다 **최고가 매매 한 건**을 거래 요약과 같은 자리에서 센다 (2026-10-21, 오류 8M0F-STDC)
   ★ 왜: AI 검색 "서울에서 제일 비싼 …" 이 60초를 넘겼다(부하 없이 재도 60초+). 지역이 시·도라 조건이 안 걸리면
     단지 53만 개마다 실거래 1,060만 건에서 최고가를 찾은 **뒤에** 줄을 세운다.
   ★ 캐시가 아니다 — trade_cnt · trade_last_amt 와 같은 **거래 요약**이고, 같은 프로시저(usp_refresh_complex_trade)가
     같은 때(실거래 적재 끝 · 283 · 287) 다시 센다. 규칙도 화면과 같다: 매매(is_rent=0) · 해제 제외 · 금액 있는 것 ·
     금액 큰 순 첫 건. 평당가는 그 거래의 면적(전용 > 연면적 > 건물면적)으로.
   ★ 종류별(아파트 · 연립 · 오피스텔 · 전체)로 따로 둔다 — AI 검색의 '아파트만' 같은 조건이 있어서.
   ★ 화면은 이걸로 **후보만** 고르고, 보여 주는 값은 지금처럼 그 자리에서 다시 읽는다(값이 둘로 갈리지 않게).
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
IF OBJECT_ID('gold.complex_trade_max') IS NULL
CREATE TABLE gold.complex_trade_max (
    종류        VARCHAR(4)     NOT NULL,     -- ALL | APT | RH | OFFI
    complex_id  INT            NOT NULL,
    max_amt     BIGINT         NOT NULL,
    max_ymd     CHAR(8)        NULL,
    max_unit    DECIMAL(19,2)  NULL,
    CONSTRAINT pk_complex_trade_max PRIMARY KEY CLUSTERED (종류, complex_id)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_ctm_amt')
    CREATE INDEX ix_ctm_amt ON gold.complex_trade_max (종류, max_amt DESC);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_ctm_unit')
    CREATE INDEX ix_ctm_unit ON gold.complex_trade_max (종류, max_unit DESC);
GO
CREATE OR ALTER PROCEDURE gold.usp_refresh_complex_trade
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

    /* ★ 288: 최고가 매매 한 건 — 종류별 */
    IF OBJECT_ID('tempdb..#mx') IS NOT NULL DROP TABLE #mx;
    SELECT 종류 = g.종류, cid = r.match_complex_id, r.deal_amount, r.deal_ymd,
           unit = CASE WHEN COALESCE(r.exclu_use_ar, r.total_floor_ar, r.building_ar) > 0
                       THEN r.deal_amount / (COALESCE(r.exclu_use_ar, r.total_floor_ar, r.building_ar) / 3.3058) END,
           rn = ROW_NUMBER() OVER (PARTITION BY g.종류, r.match_complex_id ORDER BY r.deal_amount DESC, r.deal_ymd DESC)
      INTO #mx
      FROM silver.rtms_trade r
      CROSS APPLY (SELECT 'ALL' UNION ALL
                   SELECT CASE WHEN r.trade_kind IN ('APT_TRADE_DEV','APT_TRADE') THEN 'APT'
                               WHEN r.trade_kind LIKE 'RH_%' THEN 'RH'
                               WHEN r.trade_kind LIKE 'OFFI_%' THEN 'OFFI' END) g(종류)
     WHERE r.match_complex_id IS NOT NULL AND r.is_rent = 0 AND r.is_canceled = 0
       AND r.deal_amount IS NOT NULL AND g.종류 IS NOT NULL;
    BEGIN TRAN;
        DELETE FROM gold.complex_trade_max;
        INSERT INTO gold.complex_trade_max (종류, complex_id, max_amt, max_ymd, max_unit)
        SELECT 종류, cid, deal_amount, deal_ymd, unit FROM #mx WHERE rn = 1;
    COMMIT;
END
GO
EXEC gold.usp_refresh_complex_trade;
GO
SET NOCOUNT ON;
SELECT 종류, 단지 = COUNT(*), 최고 = MAX(max_amt) FROM gold.complex_trade_max GROUP BY 종류;
GO
