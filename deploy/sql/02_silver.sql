SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* ============================================================
   Teomoony - 02_silver : 정규화 레이어
   기준(master) = 건축물대장.  나머지 축은 여기서 파생된 키로 붙는다.

   이력 정책 (SCD Type 2)
     valid_from / valid_to / is_current / row_hash
     - 공공데이터는 "조회 시점"이 곧 사실이 아니다. crtn_day(생성일자)가
       원천의 기준일이므로 둘을 분리해서 보관한다.
     - row_hash 가 바뀌지 않으면 UPDATE 하지 않는다 = 무의미한 버전 폭증 방지.
   ============================================================ */
USE Teomoony;
GO

/* ============================================================
   1) 표제부  getBrTitleInfo
      동(棟) 단위. 단지코드가 최종적으로 묶어야 하는 대상.
   ============================================================ */
IF OBJECT_ID('silver.bld_title') IS NULL
CREATE TABLE silver.bld_title (
    bld_title_sk     BIGINT IDENTITY(1,1) NOT NULL,
    mgm_bldrgst_pk   VARCHAR(50)   NOT NULL,   -- 관리건축물대장PK (동 식별자)
    mgm_up_bldrgst_pk VARCHAR(50)  NULL,       -- 상위(총괄표제부) PK
    /* --- 대장 구분 --- */
    regstr_gb_cd     VARCHAR(2)    NULL,       -- 1 일반 / 2 집합
    regstr_gb_nm     NVARCHAR(40)  NULL,
    regstr_kind_cd   VARCHAR(2)    NULL,       -- 1 일반 / 2 표제부 / 3 총괄표제부
    regstr_kind_nm   NVARCHAR(40)  NULL,
    /* --- 지번 축 (PNU 원천) --- */
    sigungu_cd       CHAR(5)       NULL,
    bjdong_cd        CHAR(5)       NULL,
    plat_gb_cd       VARCHAR(1)    NULL,       -- 0 대지 / 1 산 / 2 블록
    bun              VARCHAR(10)   NULL,
    ji               VARCHAR(10)   NULL,
    pnu              CHAR(19)      NULL,       -- meta.fn_make_pnu 결과를 ETL이 채운다
    plat_plc         NVARCHAR(300) NULL,       -- 대지위치(지번주소)
    bylot_cnt        INT           NULL,       -- 관련지번 수
    /* --- 도로명 축 (도로명주소 조인 키) ---
       naRoadCd + naUgrndCd + naMainBun + naSubBun 4개 조합이
       도로명주소 체계의 건물 식별 키다. 건축물대장이 이걸 직접 준다. */
    na_road_cd       CHAR(12)      NULL,       -- 도로명코드
    na_bjdong_cd     CHAR(5)       NULL,
    na_ugrnd_cd      VARCHAR(1)    NULL,       -- 0 지상 / 1 지하
    na_main_bun      INT           NULL,       -- 건물본번
    na_sub_bun       INT           NULL,       -- 건물부번
    new_plat_plc     NVARCHAR(300) NULL,       -- 도로명대지위치
    /* --- 명칭 --- */
    bld_nm           NVARCHAR(200) NULL,
    dong_nm          NVARCHAR(100) NULL,
    splot_nm         NVARCHAR(100) NULL,
    block            NVARCHAR(40)  NULL,
    lot              NVARCHAR(40)  NULL,
    /* --- 면적/비율 --- */
    plat_area        DECIMAL(19,5) NULL,       -- 대지면적
    arch_area        DECIMAL(19,5) NULL,       -- 건축면적
    bc_rat           DECIMAL(9,5)  NULL,       -- 건폐율
    tot_area         DECIMAL(19,5) NULL,       -- 연면적
    vl_rat_estm_tot_area DECIMAL(19,5) NULL,   -- 용적률산정연면적
    vl_rat           DECIMAL(9,5)  NULL,       -- 용적률
    tot_dong_tot_area DECIMAL(19,5) NULL,
    /* --- 구조/용도 --- */
    strct_cd         VARCHAR(10)   NULL,
    strct_nm         NVARCHAR(100) NULL,
    etc_strct        NVARCHAR(200) NULL,
    main_purps_cd    VARCHAR(10)   NULL,
    main_purps_nm    NVARCHAR(100) NULL,
    etc_purps        NVARCHAR(400) NULL,
    roof_cd          VARCHAR(10)   NULL,
    roof_nm          NVARCHAR(100) NULL,
    etc_roof         NVARCHAR(200) NULL,
    /* --- 규모 --- */
    hhld_cnt         INT           NULL,       -- 세대수
    fmly_cnt         INT           NULL,       -- 가구수
    ho_cnt           INT           NULL,       -- 호수
    heit             DECIMAL(13,3) NULL,
    grnd_flr_cnt     INT           NULL,
    ugrnd_flr_cnt    INT           NULL,
    ride_use_elvt_cnt INT          NULL,
    emgen_use_elvt_cnt INT         NULL,
    atch_bld_cnt     INT           NULL,
    atch_bld_area    DECIMAL(19,5) NULL,
    /* --- 주차 --- */
    indr_mech_utcnt  INT           NULL, indr_mech_area DECIMAL(19,5) NULL,
    oudr_mech_utcnt  INT           NULL, oudr_mech_area DECIMAL(19,5) NULL,
    indr_auto_utcnt  INT           NULL, indr_auto_area DECIMAL(19,5) NULL,
    oudr_auto_utcnt  INT           NULL, oudr_auto_area DECIMAL(19,5) NULL,
    /* --- 일자 --- */
    pms_day          CHAR(8)       NULL,       -- 허가일
    stcns_day        CHAR(8)       NULL,       -- 착공일
    use_apr_day      CHAR(8)       NULL,       -- 사용승인일
    pmsno_year       CHAR(4)       NULL,
    pmsno_kik_cd     VARCHAR(20)   NULL,
    pmsno_gb_cd      VARCHAR(10)   NULL,
    /* --- 에너지/인증 --- */
    engr_grade       NVARCHAR(40)  NULL,
    engr_rat         DECIMAL(13,3) NULL,
    engr_epi         DECIMAL(13,3) NULL,
    gn_bld_grade     NVARCHAR(40)  NULL,
    gn_bld_cert      DECIMAL(13,3) NULL,
    itg_bld_grade    NVARCHAR(40)  NULL,
    itg_bld_cert     DECIMAL(13,3) NULL,
    /* --- 원천 기준일 / 이력 --- */
    crtn_day         CHAR(8)       NULL,       -- 원천 생성일자 (현행화 판단 기준)
    row_hash         BINARY(32)    NOT NULL,
    src_run_id       BIGINT        NULL,
    valid_from       DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    valid_to         DATETIME2(0)  NOT NULL DEFAULT '9999-12-31',
    is_current       BIT           NOT NULL DEFAULT 1,
    CONSTRAINT pk_bld_title PRIMARY KEY CLUSTERED (bld_title_sk)
);
GO
/* 현재행 1건만 허용 - 중복 적재를 DB가 막는다 */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='uq_bld_title_current')
CREATE UNIQUE INDEX uq_bld_title_current ON silver.bld_title (mgm_bldrgst_pk)
    WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_bld_title_pnu')
CREATE INDEX ix_bld_title_pnu ON silver.bld_title (pnu) INCLUDE (mgm_bldrgst_pk, bld_nm) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_bld_title_up')
CREATE INDEX ix_bld_title_up ON silver.bld_title (mgm_up_bldrgst_pk) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_bld_title_road')
CREATE INDEX ix_bld_title_road ON silver.bld_title (na_road_cd, na_ugrnd_cd, na_main_bun, na_sub_bun) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_bld_title_sgg')
CREATE INDEX ix_bld_title_sgg ON silver.bld_title (sigungu_cd, bjdong_cd) WHERE is_current = 1;
GO

/* ============================================================
   2) 총괄표제부  getBrRecapTitleInfo
      여러 동을 묶는 단위. 자체 단지코드의 1차 후보 근거.
   ============================================================ */
IF OBJECT_ID('silver.bld_recap_title') IS NULL
CREATE TABLE silver.bld_recap_title (
    recap_sk         BIGINT IDENTITY(1,1) NOT NULL,
    mgm_bldrgst_pk   VARCHAR(50)   NOT NULL,   -- 총괄표제부 자신의 PK
    sigungu_cd       CHAR(5)       NULL,
    bjdong_cd        CHAR(5)       NULL,
    plat_gb_cd       VARCHAR(1)    NULL,
    bun              VARCHAR(10)   NULL,
    ji               VARCHAR(10)   NULL,
    pnu              CHAR(19)      NULL,
    plat_plc         NVARCHAR(300) NULL,
    new_plat_plc     NVARCHAR(300) NULL,
    bld_nm           NVARCHAR(200) NULL,
    regstr_gb_cd     VARCHAR(2)    NULL,
    regstr_kind_cd   VARCHAR(2)    NULL,
    plat_area        DECIMAL(19,5) NULL,
    arch_area        DECIMAL(19,5) NULL,
    bc_rat           DECIMAL(9,5)  NULL,
    tot_area         DECIMAL(19,5) NULL,
    vl_rat           DECIMAL(9,5)  NULL,
    main_bld_cnt     INT           NULL,       -- 주건축물수
    atch_bld_cnt     INT           NULL,
    atch_bld_area    DECIMAL(19,5) NULL,
    hhld_cnt         INT           NULL,
    fmly_cnt         INT           NULL,
    ho_cnt           INT           NULL,
    use_apr_day      CHAR(8)       NULL,
    pms_day          CHAR(8)       NULL,
    stcns_day        CHAR(8)       NULL,
    crtn_day         CHAR(8)       NULL,
    row_hash         BINARY(32)    NOT NULL,
    src_run_id       BIGINT        NULL,
    valid_from       DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    valid_to         DATETIME2(0)  NOT NULL DEFAULT '9999-12-31',
    is_current       BIT           NOT NULL DEFAULT 1,
    CONSTRAINT pk_bld_recap PRIMARY KEY CLUSTERED (recap_sk)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='uq_bld_recap_current')
CREATE UNIQUE INDEX uq_bld_recap_current ON silver.bld_recap_title (mgm_bldrgst_pk) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_bld_recap_pnu')
CREATE INDEX ix_bld_recap_pnu ON silver.bld_recap_title (pnu) WHERE is_current = 1;
GO

/* ============================================================
   3) 부속지번  getBrAtchJibunInfo
      ★ 단지 ↔ 토지 n:m 의 근거.
      한 단지가 여러 필지에 걸치는 경우가 정상이고, 이 테이블 없이는
      단지-토지 연계가 대표지번 1개로 뭉개진다.
   ============================================================ */
IF OBJECT_ID('silver.bld_atch_jibun') IS NULL
CREATE TABLE silver.bld_atch_jibun (
    atch_sk          BIGINT IDENTITY(1,1) NOT NULL,
    mgm_bldrgst_pk   VARCHAR(50)   NOT NULL,
    atch_sigungu_cd  CHAR(5)       NULL,
    atch_bjdong_cd   CHAR(5)       NULL,
    atch_plat_gb_cd  VARCHAR(1)    NULL,
    atch_bun         VARCHAR(10)   NULL,
    atch_ji          VARCHAR(10)   NULL,
    atch_pnu         CHAR(19)      NULL,       -- 부속지번의 PNU
    plat_plc         NVARCHAR(300) NULL,
    atch_gb_cd       VARCHAR(2)    NULL,       -- 관련지번 구분
    crtn_day         CHAR(8)       NULL,
    row_hash         BINARY(32)    NOT NULL,
    src_run_id       BIGINT        NULL,
    valid_from       DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    valid_to         DATETIME2(0)  NOT NULL DEFAULT '9999-12-31',
    is_current       BIT           NOT NULL DEFAULT 1,
    CONSTRAINT pk_bld_atch PRIMARY KEY CLUSTERED (atch_sk)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='uq_bld_atch_current')
CREATE UNIQUE INDEX uq_bld_atch_current ON silver.bld_atch_jibun (mgm_bldrgst_pk, atch_pnu) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_bld_atch_pnu')
CREATE INDEX ix_bld_atch_pnu ON silver.bld_atch_jibun (atch_pnu) WHERE is_current = 1;
GO

/* ============================================================
   4) 층별개요  getBrFlrOulnInfo
   ============================================================ */
IF OBJECT_ID('silver.bld_flr_outline') IS NULL
CREATE TABLE silver.bld_flr_outline (
    flr_sk           BIGINT IDENTITY(1,1) NOT NULL,
    mgm_bldrgst_pk   VARCHAR(50)   NOT NULL,
    flr_gb_cd        VARCHAR(2)    NULL,       -- 10 지하 / 20 지상 ...
    flr_gb_nm        NVARCHAR(40)  NULL,
    flr_no           INT           NULL,
    flr_no_nm        NVARCHAR(40)  NULL,
    strct_cd         VARCHAR(10)   NULL,
    strct_nm         NVARCHAR(100) NULL,
    etc_strct        NVARCHAR(200) NULL,
    main_purps_cd    VARCHAR(10)   NULL,
    main_purps_nm    NVARCHAR(100) NULL,
    etc_purps        NVARCHAR(400) NULL,
    area             DECIMAL(19,5) NULL,
    area_excl_yn     VARCHAR(1)    NULL,
    crtn_day         CHAR(8)       NULL,
    row_hash         BINARY(32)    NOT NULL,
    src_run_id       BIGINT        NULL,
    valid_from       DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    valid_to         DATETIME2(0)  NOT NULL DEFAULT '9999-12-31',
    is_current       BIT           NOT NULL DEFAULT 1,
    CONSTRAINT pk_bld_flr PRIMARY KEY CLUSTERED (flr_sk)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_bld_flr_pk')
CREATE INDEX ix_bld_flr_pk ON silver.bld_flr_outline (mgm_bldrgst_pk) WHERE is_current = 1;
GO

/* ============================================================
   5) 전유공용면적  getBrExposPubuseAreaInfo
      호(戶) 단위. 집합건물에서 등기와 붙는 유일한 접점이 여기다.
   ============================================================ */
IF OBJECT_ID('silver.bld_expos_pubuse_area') IS NULL
CREATE TABLE silver.bld_expos_pubuse_area (
    expos_sk         BIGINT IDENTITY(1,1) NOT NULL,
    mgm_bldrgst_pk   VARCHAR(50)   NOT NULL,
    dong_nm          NVARCHAR(100) NULL,
    ho_nm            NVARCHAR(100) NULL,
    flr_gb_cd        VARCHAR(2)    NULL,
    flr_no           INT           NULL,
    expos_pubuse_gb_cd VARCHAR(2)  NULL,       -- 1 전유 / 2 공용
    main_atch_gb_cd  VARCHAR(2)    NULL,       -- 1 주건축물 / 2 부속건축물
    strct_cd         VARCHAR(10)   NULL,
    strct_nm         NVARCHAR(100) NULL,
    main_purps_cd    VARCHAR(10)   NULL,
    main_purps_nm    NVARCHAR(100) NULL,
    etc_purps        NVARCHAR(400) NULL,
    area             DECIMAL(19,5) NULL,
    crtn_day         CHAR(8)       NULL,
    row_hash         BINARY(32)    NOT NULL,
    src_run_id       BIGINT        NULL,
    valid_from       DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    valid_to         DATETIME2(0)  NOT NULL DEFAULT '9999-12-31',
    is_current       BIT           NOT NULL DEFAULT 1,
    CONSTRAINT pk_bld_expos PRIMARY KEY CLUSTERED (expos_sk)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_bld_expos_pk')
CREATE INDEX ix_bld_expos_pk ON silver.bld_expos_pubuse_area (mgm_bldrgst_pk, dong_nm, ho_nm) WHERE is_current = 1;
GO

/* ============================================================
   6) 토지 (토지특성정보 / 개별공시지가)  -- 키: PNU
   ============================================================ */
IF OBJECT_ID('silver.land_char') IS NULL
CREATE TABLE silver.land_char (
    land_sk          BIGINT IDENTITY(1,1) NOT NULL,
    pnu              CHAR(19)      NOT NULL,
    base_year        CHAR(4)       NULL,       -- 기준연도 (공시지가는 연단위)
    base_month       CHAR(2)       NULL,
    ld_code_nm       NVARCHAR(200)  NULL,
    mnnm_slno        NVARCHAR(40)  NULL,       -- 지번
    regstr_se_code   VARCHAR(2)    NULL,       -- 대장구분(토지/임야)
    lndcgr_code      VARCHAR(4)    NULL,       -- 지목 코드
    lndcgr_nm        NVARCHAR(40)  NULL,
    lndpcl_ar        DECIMAL(19,5) NULL,       -- 토지면적
    prpos_area1_nm   NVARCHAR(100) NULL,       -- 용도지역1
    prpos_area2_nm   NVARCHAR(100) NULL,
    lad_use_sittn_nm NVARCHAR(100) NULL,       -- 토지이용상황
    tpgrph_hg_code_nm NVARCHAR(40) NULL,       -- 지형고저
    tpgrph_frm_code_nm NVARCHAR(40) NULL,      -- 지형형상
    road_side_code_nm NVARCHAR(40) NULL,       -- 도로접면
    pblntf_pclnd     DECIMAL(19,2) NULL,       -- 개별공시지가(원/m2)
    last_updt_dt     CHAR(8)       NULL,
    row_hash         BINARY(32)    NOT NULL,
    src_run_id       BIGINT        NULL,
    valid_from       DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    valid_to         DATETIME2(0)  NOT NULL DEFAULT '9999-12-31',
    is_current       BIT           NOT NULL DEFAULT 1,
    CONSTRAINT pk_land_char PRIMARY KEY CLUSTERED (land_sk)
);
GO

/* ============================================================
   7) 도로명주소 (지번 <-> 도로명 연계)
      juso.go.kr 의 "주소연계" 자료 구조.
      ★ API 키가 공공데이터포털과 별개(도로명주소 개발자센터)이고,
        대량 매칭은 API가 아니라 월배치 전체분/변동분 파일이 정답.
   ============================================================ */
IF OBJECT_ID('silver.road_addr') IS NULL
CREATE TABLE silver.road_addr (
    road_addr_sk     BIGINT IDENTITY(1,1) NOT NULL,
    bld_mgt_no       CHAR(25)      NOT NULL,   -- 건물관리번호 25
    /* 도로명 측 키 - 건축물대장 na_* 와 직접 조인되는 부분 */
    road_cd          CHAR(12)      NULL,
    ugrnd_yn         VARCHAR(1)    NULL,       -- 0 지상 / 1 지하
    bld_main_no      INT           NULL,       -- 건물본번
    bld_sub_no       INT           NULL,       -- 건물부번
    /* 지번 측 키 */
    pnu              CHAR(19)      NULL,       -- 연계되는 지번의 PNU
    lawd_cd          CHAR(10)      NULL,
    san_yn           VARCHAR(1)    NULL,
    jibun_main_no    INT           NULL,
    jibun_sub_no     INT           NULL,
    /* 표기 */
    road_nm          NVARCHAR(80)  NULL,
    emd_nm           NVARCHAR(40)  NULL,
    li_nm            NVARCHAR(40)  NULL,
    bld_nm           NVARCHAR(200) NULL,
    detail_bld_nm    NVARCHAR(400) NULL,
    zip_no           CHAR(5)       NULL,
    road_addr_full   NVARCHAR(400) NULL,
    jibun_addr_full  NVARCHAR(400) NULL,
    /* 대표여부 - 한 건물관리번호에 여러 지번이 달릴 수 있다 */
    is_representative BIT          NOT NULL DEFAULT 0,
    mvmn_de          CHAR(8)       NULL,       -- 이동일자(변동분 추적)
    mvmn_reason_cd   VARCHAR(2)    NULL,       -- 31 신규 / 34 변경 / 63 폐지 ...
    row_hash         BINARY(32)    NOT NULL,
    src_run_id       BIGINT        NULL,
    valid_from       DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    valid_to         DATETIME2(0)  NOT NULL DEFAULT '9999-12-31',
    is_current       BIT           NOT NULL DEFAULT 1,
    CONSTRAINT pk_road_addr PRIMARY KEY CLUSTERED (road_addr_sk)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_road_addr_key')
CREATE INDEX ix_road_addr_key ON silver.road_addr (road_cd, ugrnd_yn, bld_main_no, bld_sub_no) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_road_addr_pnu')
CREATE INDEX ix_road_addr_pnu ON silver.road_addr (pnu) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_road_addr_mgtno')
CREATE INDEX ix_road_addr_mgtno ON silver.road_addr (bld_mgt_no) WHERE is_current = 1;
GO

/* ============================================================
   8) 등기 — **폐기했다** (2026-10-20)
      스텁으로 구조만 선점해 뒀었는데 **채울 길이 없다**:
        * 공공데이터포털에 등기부등본 오픈API 가 없다
        * 등기는 부동산고유번호(14)를 쓰고 PNU(19)와 직접 매칭이 안 된다
          -> 주소 문자열 정규화 매칭이 필요한데, 그건 정책 1장(코드로만 잇는다)에
             어긋난다. 조용히 틀린 매칭은 NULL 보다 나쁘다.
        * 스크래핑은 쓰지 않는다 (정책 1장)
      실측 2026-10-20: silver.registry_property 0건. 2년을 비워 둘 표였다.
      ★ 되살리지 말 것. 공공 API 가 생기면 그때 새로 설계한다.
         (지우는 SQL: deploy/sql/210_drop_registry.sql)
   ============================================================ */

PRINT '02_silver done.';
GO
