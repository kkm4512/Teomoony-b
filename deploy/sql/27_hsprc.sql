SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* ============================================================
   27_hsprc : 주택가격(공시가격) — 2026-10-17

   ★ **호 단위 PK 다.** getBrHsprcInfo 의 mgmBldrgstPk 는 전유부와 같은 키라
     silver.bld_expos 에 코드로 그대로 붙는다. 문자열 매칭이 없다.

        hsprc   219000000      공시가격
        stdDay  20150101       기준일 (매년 1월 1일)
        같은 PK 가 ~20회 반복   2006~2026

   ★ 정책.md 4-3 이 "동별 시세 차이는 못 보여준다" 고 포기한 것은 **실거래** 얘기다
     (aptDong 이 아파트 매매에만 있다). **공시가격은 호 단위라 동·라인·층까지
     완전히 떨어진다.** 포기한 것과 다른 축이다.

   ★ 공시가격은 **실거래가가 아니다.** 과세표준용이라 실거래의 60~70% 수준이다.
     - **단지 간 비교에 쓰지 않는다.** 개별사용료를 단지 간 비교에서 제외한 것과 같다
     - 쓰는 곳은 **같은 단지 안에서 층·라인별 상대 차이**다. 그래서 뷰가 금액과
       함께 **단지 내 분위**를 같이 준다 — 절대금액으로 칠하면 단지마다 색이
       달라져 비교가 안 된다
     - 한 단지 안에도 평형이 섞여 있다. **같은 라인 안에서 세로(층)로 읽는 것**이
       순수한 층 프리미엄이고, 라인 간 비교에는 평형 차이가 섞인다
   ============================================================ */
USE Teomoony;
GO

IF OBJECT_ID('silver.bld_hsprc') IS NULL
CREATE TABLE silver.bld_hsprc (
    hsprc_sk         BIGINT IDENTITY(1,1) NOT NULL,
    mgm_bldrgst_pk   VARCHAR(50)   NOT NULL,   -- 호 단위 PK (전유부와 같은 키)
    std_day          CHAR(8)       NOT NULL,   -- 기준일. 매년 0101
    hsprc            DECIMAL(19,0) NULL,       -- 공시가격(원)
    sigungu_cd       CHAR(5)       NULL,
    bjdong_cd        CHAR(5)       NULL,
    plat_gb_cd       VARCHAR(1)    NULL,
    bun              VARCHAR(10)   NULL,
    ji               VARCHAR(10)   NULL,
    pnu              CHAR(19)      NULL,
    plat_plc         NVARCHAR(300) NULL,
    bld_nm           NVARCHAR(200) NULL,
    regstr_gb_cd     VARCHAR(2)    NULL,
    regstr_kind_cd   VARCHAR(2)    NULL,
    crtn_day         CHAR(8)       NULL,
    row_hash         BINARY(32)    NOT NULL,
    src_run_id       BIGINT        NULL,
    valid_from       DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    valid_to         DATETIME2(0)  NOT NULL DEFAULT '9999-12-31',
    is_current       BIT           NOT NULL DEFAULT 1,
    CONSTRAINT pk_bld_hsprc PRIMARY KEY CLUSTERED (hsprc_sk)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='uq_bld_hsprc_current')
CREATE UNIQUE INDEX uq_bld_hsprc_current ON silver.bld_hsprc (mgm_bldrgst_pk, std_day)
    WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_bld_hsprc_pnu')
CREATE INDEX ix_bld_hsprc_pnu ON silver.bld_hsprc (pnu) WHERE is_current = 1;
GO

/* ---------- 호별 최신 공시가격 ----------
   `분위`는 **그 단지 안에서의** 5분위다. 절대금액으로 칠하면 단지마다 색이
   달라져 비교가 안 되므로, 화면은 분위로 칠하고 금액은 툴팁에 적는다. */
IF OBJECT_ID('gold.v_complex_ho_price') IS NOT NULL DROP VIEW gold.v_complex_ho_price;
GO
CREATE VIEW gold.v_complex_ho_price
AS
WITH l AS (
    SELECT mgm_bldrgst_pk, std_day, hsprc,
           rn = ROW_NUMBER() OVER (PARTITION BY mgm_bldrgst_pk ORDER BY std_day DESC)
    FROM silver.bld_hsprc
    WHERE is_current = 1 AND hsprc > 0
),
j AS (
    SELECT h.complex_id, h.호PK, h.동PK, h.동, h.층, h.호, h.라인,
           기준일 = l.std_day, 공시가격 = l.hsprc
    FROM gold.v_complex_ho h
    JOIN l ON l.mgm_bldrgst_pk = h.호PK AND l.rn = 1
)
SELECT j.*,
       단지분위 = NTILE(5) OVER (PARTITION BY j.complex_id       ORDER BY j.공시가격),
       /* 같은 라인 안은 평형이 같은 경우가 대부분이라, 세로로 읽으면
          **순수한 층 프리미엄**이 보인다. 라인 간에는 평형 차이가 섞인다. */
       라인분위 = NTILE(5) OVER (PARTITION BY j.complex_id, j.동PK, j.라인 ORDER BY j.공시가격)
FROM j;
GO

PRINT '--- 적재 후 점검 ---';
SELECT 호=COUNT(*), 가격있음=COUNT(공시가격),
       최신기준일=MAX(기준일), 최저=MIN(공시가격), 최고=MAX(공시가격)
FROM gold.v_complex_ho_price;
GO

PRINT '27_hsprc done.';
GO
