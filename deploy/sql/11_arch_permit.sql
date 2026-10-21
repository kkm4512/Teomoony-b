SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* ============================================================
   11_arch_permit : 건축인허가 (건축HUB)

   출처 : https://apis.data.go.kr/1613000/ArchPmsHubService
          getApBasisOulnInfo (기본개요) / getApDongOulnInfo (동별개요)
          * 별도 활용신청이 필요하다. 건축물대장과 같은 키를 쓰되
            서비스마다 신청이 따로다.

   ★ 왜 필요한가
     건축물대장은 "지어진 것"이고 인허가는 "지으려는 것"이다.
     신축은 거래가 먼저 일어나고 대장이 나중에 생긴다. 장위자이레디언트
     (장위동 62-1)가 그 사례로, 2025년 전월세 644건이 붙을 곳이 없었다:
         건축물대장  기본개요 0 / 표제부 0 / 총괄표제부 0
         건축인허가  기본개요 15 / 동별개요 29
     이 시차 구간을 메우는 것이 이 테이블의 목적이다.

   ★ 대장과 같은 자리에 두지 않는다
     허가만 받고 안 짓거나, 취소되거나, 설계변경으로 여러 건이 쌓인다.
     62-1 한 지번에 15건이 있다. "허가 15건 = 건물 15개"가 아니다.
     그래서 gold.complex 로 묶지 않는다. 진행 상태(허가/착공/사용승인)를
     축으로 두고, 사용승인이 찍혀 대장이 생기면 그쪽이 진실이 된다.
   ============================================================ */
USE Teomoony;
GO

/* ---------- 기본개요 : 허가 1건 = 1행 ---------- */
IF OBJECT_ID('silver.arch_permit') IS NULL
CREATE TABLE silver.arch_permit (
    permit_sk       BIGINT IDENTITY(1,1) NOT NULL,
    mgm_pmsrgst_pk  VARCHAR(50)    NOT NULL,   -- 허가대장 PK (대장 PK 와 다른 체계)
    pnu             CHAR(19)       NULL,       -- meta.fn_make_pnu() 로만 만든다
    sigungu_cd      CHAR(5)        NULL,
    bjdong_cd       CHAR(5)        NULL,
    plat_gb_cd      VARCHAR(1)     NULL,
    bun             VARCHAR(10)    NULL,
    ji              VARCHAR(10)    NULL,
    plat_plc        NVARCHAR(300)  NULL,
    bld_nm          NVARCHAR(200)  NULL,
    splot_nm        NVARCHAR(100)  NULL,
    block           NVARCHAR(40)   NULL,
    lot             NVARCHAR(40)   NULL,
    /* 지목 / 용도지역·지구·구역 — 공간 조인 없이 코드로 들어온다 */
    jimok_cd        VARCHAR(10)    NULL,
    jimok_nm        NVARCHAR(40)   NULL,
    jiyuk_cd        VARCHAR(10)    NULL,
    jiyuk_nm        NVARCHAR(80)   NULL,
    jigu_cd         VARCHAR(10)    NULL,
    jigu_nm         NVARCHAR(80)   NULL,
    guyuk_cd        VARCHAR(10)    NULL,
    guyuk_nm        NVARCHAR(80)   NULL,
    /* 허가 종류 (신축 / 증축 / 대수선 …) */
    arch_gb_cd      VARCHAR(10)    NULL,
    arch_gb_nm      NVARCHAR(40)   NULL,
    main_purps_cd   VARCHAR(10)    NULL,
    main_purps_nm   NVARCHAR(80)   NULL,
    /* 규모 */
    plat_area       DECIMAL(18,4)  NULL,
    arch_area       DECIMAL(18,4)  NULL,
    bc_rat          DECIMAL(9,4)   NULL,
    tot_area        DECIMAL(18,4)  NULL,
    vl_rat_estm_tot_area DECIMAL(18,4) NULL,
    vl_rat          DECIMAL(9,4)   NULL,
    main_bld_cnt    INT            NULL,
    atch_bld_dong_cnt INT          NULL,
    hhld_cnt        INT            NULL,
    ho_cnt          INT            NULL,
    fmly_cnt        INT            NULL,
    tot_pkng_cnt    INT            NULL,
    /* 진행 상태 — 이 테이블의 핵심 축 */
    arch_pms_day    CHAR(8)        NULL,       -- 허가
    stcns_sched_day CHAR(8)        NULL,       -- 착공예정
    real_stcns_day  CHAR(8)        NULL,       -- 실제착공
    stcns_delay_day CHAR(8)        NULL,       -- 착공기한(연기 포함) = 허가 + 2년, 연장 시 3년
                                               --   ★ '지연 일수' 가 아니다. 이 주석이 비어 있던 탓에
                                               --   프론트가 이름만 보고 일수로 읽어 화면에 
                                               --   '착공지연 20,170,910일' 을 띄웠다(2026-10-16).
                                               --   실측: 19건 중 11건이 정확히 730/1095일.
                                               --   진짜 지연 = stcns_sched_day vs real_stcns_day
    use_apr_day     CHAR(8)        NULL,       -- 사용승인 -> 이후 대장이 생긴다
    crtn_day        CHAR(8)        NULL,
    src             VARCHAR(30)    NOT NULL DEFAULT 'ARCHPMS_BASIS',
    row_hash        BINARY(32)     NOT NULL,
    src_run_id      BIGINT         NULL,
    valid_from      DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    valid_to        DATETIME2(0)   NOT NULL DEFAULT '9999-12-31',
    is_current      BIT            NOT NULL DEFAULT 1,
    CONSTRAINT pk_arch_permit PRIMARY KEY CLUSTERED (permit_sk)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='uq_arch_permit_current')
CREATE UNIQUE INDEX uq_arch_permit_current ON silver.arch_permit (mgm_pmsrgst_pk) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_arch_permit_pnu')
CREATE INDEX ix_arch_permit_pnu ON silver.arch_permit (pnu) WHERE is_current = 1;
GO

/* ---------- 동별개요 : 허가 안의 동 ---------- */
IF OBJECT_ID('silver.arch_permit_dong') IS NULL
CREATE TABLE silver.arch_permit_dong (
    permit_dong_sk  BIGINT IDENTITY(1,1) NOT NULL,
    mgm_dong_ouln_pk VARCHAR(50)   NOT NULL,
    mgm_pmsrgst_pk  VARCHAR(50)    NULL,
    pnu             CHAR(19)       NULL,
    sigungu_cd      CHAR(5)        NULL,
    bjdong_cd       CHAR(5)        NULL,
    plat_gb_cd      VARCHAR(1)     NULL,
    bun             VARCHAR(10)    NULL,
    ji              VARCHAR(10)    NULL,
    plat_plc        NVARCHAR(300)  NULL,
    bld_nm          NVARCHAR(200)  NULL,
    main_atch_gb_cd VARCHAR(10)    NULL,
    main_atch_gb_nm NVARCHAR(40)   NULL,
    main_purps_cd   VARCHAR(10)    NULL,
    main_purps_nm   NVARCHAR(80)   NULL,
    strct_cd        VARCHAR(10)    NULL,
    strct_nm        NVARCHAR(80)   NULL,
    roof_cd         VARCHAR(10)    NULL,
    roof_nm         NVARCHAR(80)   NULL,
    arch_area       DECIMAL(18,4)  NULL,
    tot_area        DECIMAL(18,4)  NULL,
    vl_rat_estm_tot_area DECIMAL(18,4) NULL,
    hhld_cnt        INT            NULL,
    ho_cnt          INT            NULL,
    fmly_cnt        INT            NULL,
    ride_use_elvt_cnt INT          NULL,
    emgen_use_elvt_cnt INT         NULL,
    crtn_day        CHAR(8)        NULL,
    src             VARCHAR(30)    NOT NULL DEFAULT 'ARCHPMS_DONG',
    row_hash        BINARY(32)     NOT NULL,
    src_run_id      BIGINT         NULL,
    valid_from      DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    valid_to        DATETIME2(0)   NOT NULL DEFAULT '9999-12-31',
    is_current      BIT            NOT NULL DEFAULT 1,
    CONSTRAINT pk_arch_permit_dong PRIMARY KEY CLUSTERED (permit_dong_sk)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='uq_arch_permit_dong_current')
CREATE UNIQUE INDEX uq_arch_permit_dong_current ON silver.arch_permit_dong (mgm_dong_ouln_pk) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_arch_permit_dong_pms')
CREATE INDEX ix_arch_permit_dong_pms ON silver.arch_permit_dong (mgm_pmsrgst_pk) WHERE is_current = 1;
GO

/* ============================================================
   대장이 없는 자리를 인허가가 메우는가
   "실거래는 붙었는데(PNU) 단지가 없는" 지번을 인허가와 맞춰 본다.
   ============================================================ */
IF OBJECT_ID('gold.v_permit_gap') IS NOT NULL DROP VIEW gold.v_permit_gap;
GO
CREATE VIEW gold.v_permit_gap
AS
SELECT t.pnu,
       t.lawd_cd,
       거래 = t.cnt,
       대장 = ISNULL(b.cnt, 0),
       인허가 = ISNULL(p.cnt, 0),
       최근허가 = last.arch_pms_day,
       착공 = last.real_stcns_day,
       사용승인 = last.use_apr_day,
       허가구분 = last.arch_gb_nm,
       허가명 = last.bld_nm,
       허가세대 = last.hhld_cnt
FROM (
    SELECT match_pnu AS pnu, LEFT(match_pnu,10) AS lawd_cd, COUNT(*) AS cnt
    FROM silver.rtms_trade
    WHERE match_pnu IS NOT NULL AND match_complex_id IS NULL
    GROUP BY match_pnu
) t
OUTER APPLY (SELECT COUNT(*) AS cnt FROM silver.bld_basis_outline b
              WHERE b.is_current = 1 AND b.pnu = t.pnu) b
OUTER APPLY (SELECT COUNT(*) AS cnt FROM silver.arch_permit a
              WHERE a.is_current = 1 AND a.pnu = t.pnu) p
/* 컬럼마다 MAX 를 뜨면 서로 다른 허가 건의 값이 한 줄에 섞인다.
   62-1 은 재개발 전 옛 건물 허가(2005 사용승인)와 신축 허가가 함께 쌓여 있어
   "최근허가 2023 / 사용승인 2005" 라는 모순된 행이 나왔다.
   가장 최근 허가 한 건을 통째로 집어 온다. */
OUTER APPLY (
    SELECT TOP 1 a.arch_pms_day, a.use_apr_day, a.real_stcns_day,
                 a.bld_nm, a.arch_gb_nm, a.hhld_cnt
    FROM silver.arch_permit a
    WHERE a.is_current = 1 AND a.pnu = t.pnu
    ORDER BY a.arch_pms_day DESC, a.crtn_day DESC
) last;
GO
