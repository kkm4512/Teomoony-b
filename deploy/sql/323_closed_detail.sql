/* ============================================================
   323_closed_detail : 폐쇄·말소 대장의 **전유부(호) · 전유공용면적 · 층별개요** — 단지 상세처럼 동·호를 보이려고 (2026-10-23 사장님 "123 ㄱㄱ")
   출처: 공공데이터포털 15137093 ShtRgstHubService getSrExposInfo · getSrExposPubuseAreaInfo · getSrFlrOulnInfo (지번 하나씩 · 원문 그대로).
   ★ 집합(공동주택 등) 폐쇄 대장 지번만 — 옛 건물 실거래가 있는 지번 먼저(6,501), 그다음 나머지(약 1.8만).
   ★ 다 받았을 때만 넣는다(받은 줄 = totalCount). 지번마다 지우고 다시 넣는다(같은 원문을 다시 받으면 같은 결과).
   ★ 주택가격(getSrHsprcInfo)은 **안 받는다** — 응답에 기준일이 없다(가격 · 만든날만). 몇 년 가격인지 모르는 값은 안 보인다.
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
IF OBJECT_ID('silver.bld_closed_expos') IS NULL
CREATE TABLE silver.bld_closed_expos (
    mgm_shtreg_pk  VARCHAR(40)   NOT NULL CONSTRAINT pk_bld_closed_expos PRIMARY KEY,
    pnu            CHAR(19)      NOT NULL,
    shter_gb_nm    NVARCHAR(20)  NULL,
    regstr_kind_nm NVARCHAR(20)  NULL,
    bld_nm         NVARCHAR(200) NULL,
    dong_nm        NVARCHAR(100) NULL,
    ho_nm          NVARCHAR(100) NULL,
    flr_gb_nm      NVARCHAR(20)  NULL,
    flr_no         INT           NULL,
    crtn_day       CHAR(8)       NULL,
    loaded_at      DATETIME2(0)  NOT NULL CONSTRAINT df_bld_closed_expos_t DEFAULT SYSDATETIME()
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_bld_closed_expos_pnu' AND object_id = OBJECT_ID('silver.bld_closed_expos'))
    CREATE INDEX ix_bld_closed_expos_pnu ON silver.bld_closed_expos (pnu, dong_nm);
GO
IF OBJECT_ID('silver.bld_closed_expos_area') IS NULL
CREATE TABLE silver.bld_closed_expos_area (
    sk               BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT pk_bld_closed_expos_area PRIMARY KEY,
    mgm_shtreg_pk    VARCHAR(40)   NOT NULL,      -- 그 호(전유부)의 pk
    pnu              CHAR(19)      NOT NULL,
    dong_nm          NVARCHAR(100) NULL,
    ho_nm            NVARCHAR(100) NULL,
    flr_gb_nm        NVARCHAR(20)  NULL,
    flr_no           INT           NULL,
    flr_no_nm        NVARCHAR(40)  NULL,
    expos_pubuse_gb_nm NVARCHAR(20) NULL,         -- 전유 / 공용
    main_atch_gb_nm  NVARCHAR(20)  NULL,
    main_purps_nm    NVARCHAR(100) NULL,
    etc_purps        NVARCHAR(200) NULL,
    strct_nm         NVARCHAR(100) NULL,
    area             DECIMAL(19,4) NULL,
    crtn_day         CHAR(8)       NULL,
    loaded_at        DATETIME2(0)  NOT NULL CONSTRAINT df_bld_closed_expos_area_t DEFAULT SYSDATETIME()
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_bld_closed_expos_area_pnu' AND object_id = OBJECT_ID('silver.bld_closed_expos_area'))
    CREATE INDEX ix_bld_closed_expos_area_pnu ON silver.bld_closed_expos_area (pnu, mgm_shtreg_pk);
GO
IF OBJECT_ID('silver.bld_closed_flr') IS NULL
CREATE TABLE silver.bld_closed_flr (
    sk               BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT pk_bld_closed_flr PRIMARY KEY,
    mgm_shtreg_pk    VARCHAR(40)   NOT NULL,      -- 그 동(표제부)의 pk
    pnu              CHAR(19)      NOT NULL,
    dong_nm          NVARCHAR(100) NULL,
    flr_gb_nm        NVARCHAR(20)  NULL,
    flr_no           INT           NULL,
    flr_no_nm        NVARCHAR(40)  NULL,
    main_atch_gb_nm  NVARCHAR(20)  NULL,
    main_purps_nm    NVARCHAR(100) NULL,
    etc_purps        NVARCHAR(200) NULL,
    strct_nm         NVARCHAR(100) NULL,
    area             DECIMAL(19,4) NULL,
    crtn_day         CHAR(8)       NULL,
    loaded_at        DATETIME2(0)  NOT NULL CONSTRAINT df_bld_closed_flr_t DEFAULT SYSDATETIME()
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_bld_closed_flr_pnu' AND object_id = OBJECT_ID('silver.bld_closed_flr'))
    CREATE INDEX ix_bld_closed_flr_pnu ON silver.bld_closed_flr (pnu, mgm_shtreg_pk);
GO
IF OBJECT_ID('silver.bld_closed_detail_done') IS NULL
CREATE TABLE silver.bld_closed_detail_done (
    pnu       CHAR(19)     NOT NULL,
    op        VARCHAR(40)  NOT NULL,
    건수      INT          NOT NULL,
    받은때    DATETIME2(0) NOT NULL CONSTRAINT df_bld_closed_detail_done_t DEFAULT SYSDATETIME(),
    CONSTRAINT pk_bld_closed_detail_done PRIMARY KEY (pnu, op)
);
GO
/* 받을 지번 — 집합 폐쇄 대장(서울·안양) · 차례 1 = 옛 건물 실거래가 있는 지번 */
CREATE OR ALTER VIEW gold.v_closed_detail_target
AS
SELECT x.pnu, x.sigungu_cd, x.bjdong_cd, x.plat_gb_cd, x.bun, x.ji,
       차례 = CASE WHEN EXISTS (SELECT 1 FROM silver.rtms_trade r WHERE r.match_pnu = x.pnu AND r.match_complex_id IS NULL AND r.trade_kind NOT LIKE 'SILV%') THEN 1 ELSE 2 END
  FROM (SELECT pnu, sigungu_cd = MIN(sigungu_cd), bjdong_cd = MIN(bjdong_cd), plat_gb_cd = MIN(plat_gb_cd), bun = MIN(bun), ji = MIN(ji)
          FROM silver.bld_closed_title
         WHERE regstr_gb_nm = N'집합' AND pnu IS NOT NULL AND (pnu LIKE '11%' OR pnu LIKE '4117%')
         GROUP BY pnu) x;
GO
SELECT 차례, n = COUNT(*) FROM gold.v_closed_detail_target GROUP BY 차례;
