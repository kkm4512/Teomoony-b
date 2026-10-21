SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* ============================================================
   Teomoony - 05_revise
   실데이터(종로구 청운동 11110/10100) probe 결과를 반영한 개정

   확인된 사실
   ------------------------------------------------------------
   1) getBrTitleInfo 는 mgmUpBldrgstPk 를 주지 않는다.
      -> 대장 계층은 getBrBasisOulnInfo(기본개요)에만 있다.
      -> 기본개요가 연결 테이블이고, 나머지가 거기 붙는 구조로 바꾼다.

   2) mgmUpBldrgstPk = '0' 은 "부모 없음" 센티넬이다. PK 가 아니다.
      청운동 전수 899건 검증:
        전유부   527 -> 표제부      100%
        표제부    74 -> 총괄 20 / 부모없음 54 (한 동짜리 빌라)
        일반건축 285 -> 총괄 31 / 부모없음 254
        총괄표제   13 -> 최상위

   3) regstrKindCd 실제 코드값 (초기 가정이 틀렸음)
        1 = 총괄표제부
        2 = 일반건축물
        3 = 표제부
        4 = 전유부

   4) bldNm 73%, dongNm 80% 결손. 단지명을 이름 필드에만 의존 불가.

   5) API 는 페이지당 100건이 최대 (numOfRows=1000 을 줘도 100 으로 잘림).
   ============================================================ */
USE Teomoony;
GO

/* ============================================================
   A) 코드값 정정
   ============================================================ */
DELETE FROM meta.code_item WHERE code_group IN ('REGSTR_KIND','REGSTR_GB','MAIN_ATCH_GB');
GO
INSERT INTO meta.code_item (code_group, code_val, code_nm, sort_no) VALUES
 ('REGSTR_KIND','1',N'총괄표제부',1),
 ('REGSTR_KIND','2',N'일반건축물',2),
 ('REGSTR_KIND','3',N'표제부',3),
 ('REGSTR_KIND','4',N'전유부',4),
 ('REGSTR_GB','1',N'일반',1),
 ('REGSTR_GB','2',N'집합',2),
 ('MAIN_ATCH_GB','0',N'주건축물',1),
 ('MAIN_ATCH_GB','1',N'부속건축물',2);
GO

/* ============================================================
   B) 기본개요 - 대장 계층의 단일 진실 공급원
      ★ 이 테이블이 단지 묶기의 근거다.
   ============================================================ */
IF OBJECT_ID('silver.bld_basis_outline') IS NULL
CREATE TABLE silver.bld_basis_outline (
    basis_sk         BIGINT IDENTITY(1,1) NOT NULL,
    mgm_bldrgst_pk   VARCHAR(50)   NOT NULL,   -- 자기 PK
    mgm_up_bldrgst_pk VARCHAR(50)  NULL,       -- 부모 PK. '0' = 부모 없음
    /* ★ 단지 식별자 : 부모가 있으면 부모, 없으면 자기 자신.
       총괄표제부의 self_pk 와 그 자식들의 up_pk 가 같은 값이 되므로
       한 단지로 모인다. ETL 이 채운다. */
    root_bldrgst_pk  VARCHAR(50)   NULL,
    bldg_id          VARCHAR(30)   NULL,       -- 건물ID (16자리)
    regstr_gb_cd     VARCHAR(2)    NULL,
    regstr_gb_nm     NVARCHAR(40)  NULL,
    regstr_kind_cd   VARCHAR(2)    NULL,       -- 1총괄 2일반 3표제부 4전유부
    regstr_kind_nm   NVARCHAR(40)  NULL,
    /* 지번 축 */
    sigungu_cd       CHAR(5)       NULL,
    bjdong_cd        CHAR(5)       NULL,
    plat_gb_cd       VARCHAR(1)    NULL,
    bun              VARCHAR(10)   NULL,
    ji               VARCHAR(10)   NULL,
    pnu              CHAR(19)      NULL,
    plat_plc         NVARCHAR(300) NULL,
    bylot_cnt        INT           NULL,
    splot_nm         NVARCHAR(100) NULL,
    block            NVARCHAR(40)  NULL,
    lot              NVARCHAR(40)  NULL,
    /* 도로명 축 */
    na_road_cd       CHAR(12)      NULL,
    na_bjdong_cd     CHAR(5)       NULL,
    na_ugrnd_cd      VARCHAR(1)    NULL,
    na_main_bun      INT           NULL,
    na_sub_bun       INT           NULL,
    new_plat_plc     NVARCHAR(300) NULL,
    bld_nm           NVARCHAR(200) NULL,
    /* 지역지구구역 */
    jiyuk_cd         VARCHAR(20)   NULL, jiyuk_nm NVARCHAR(100) NULL,
    jigu_cd          VARCHAR(20)   NULL, jigu_nm  NVARCHAR(100) NULL,
    guyuk_cd         VARCHAR(20)   NULL, guyuk_nm NVARCHAR(100) NULL,
    crtn_day         CHAR(8)       NULL,
    row_hash         BINARY(32)    NOT NULL,
    src_run_id       BIGINT        NULL,
    valid_from       DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    valid_to         DATETIME2(0)  NOT NULL DEFAULT '9999-12-31',
    is_current       BIT           NOT NULL DEFAULT 1,
    CONSTRAINT pk_bld_basis PRIMARY KEY CLUSTERED (basis_sk)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='uq_bld_basis_current')
CREATE UNIQUE INDEX uq_bld_basis_current ON silver.bld_basis_outline (mgm_bldrgst_pk) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_bld_basis_root')
CREATE INDEX ix_bld_basis_root ON silver.bld_basis_outline (root_bldrgst_pk)
    INCLUDE (mgm_bldrgst_pk, regstr_kind_cd, pnu, bld_nm) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_bld_basis_up')
CREATE INDEX ix_bld_basis_up ON silver.bld_basis_outline (mgm_up_bldrgst_pk) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_bld_basis_pnu')
CREATE INDEX ix_bld_basis_pnu ON silver.bld_basis_outline (pnu) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_bld_basis_sgg')
CREATE INDEX ix_bld_basis_sgg ON silver.bld_basis_outline (sigungu_cd, bjdong_cd) WHERE is_current = 1;
GO

/* ============================================================
   C) 표제부 - 실제 응답에 맞춰 보정
   ============================================================ */
/* getBrTitleInfo 는 이 값을 주지 않는다. 계층은 기본개요에서 읽는다.
   컬럼을 남겨두면 "비어 있는 게 정상인데 버그로 오인"하는 함정이 되므로 제거. */
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_bld_title_up')
    DROP INDEX ix_bld_title_up ON silver.bld_title;
GO
IF COL_LENGTH('silver.bld_title','mgm_up_bldrgst_pk') IS NOT NULL
    ALTER TABLE silver.bld_title DROP COLUMN mgm_up_bldrgst_pk;
GO

IF COL_LENGTH('silver.bld_title','main_atch_gb_cd') IS NULL
ALTER TABLE silver.bld_title ADD
    main_atch_gb_cd        VARCHAR(2)   NULL,   -- 0 주건축물 / 1 부속건축물
    main_atch_gb_nm        NVARCHAR(40) NULL,
    pmsno_gb_nm            NVARCHAR(80) NULL,
    pmsno_kik_nm           NVARCHAR(80) NULL,
    rserthqk_dsgn_apply_yn VARCHAR(10)  NULL,   -- 내진설계 적용여부
    rserthqk_ablty         NVARCHAR(100) NULL;  -- 내진능력
GO

/* ============================================================
   D) 총괄표제부 - 실제 응답에 맞춰 보강
   ============================================================ */
IF COL_LENGTH('silver.bld_recap_title','na_road_cd') IS NULL
ALTER TABLE silver.bld_recap_title ADD
    na_road_cd          CHAR(12)      NULL,
    na_bjdong_cd        CHAR(5)       NULL,
    na_ugrnd_cd         VARCHAR(1)    NULL,
    na_main_bun         INT           NULL,
    na_sub_bun          INT           NULL,
    regstr_gb_nm        NVARCHAR(40)  NULL,
    regstr_kind_nm      NVARCHAR(40)  NULL,
    new_old_regstr_gb_cd VARCHAR(2)   NULL,
    new_old_regstr_gb_nm NVARCHAR(40) NULL,
    main_purps_cd       VARCHAR(10)   NULL,
    main_purps_nm       NVARCHAR(100) NULL,
    etc_purps           NVARCHAR(400) NULL,
    splot_nm            NVARCHAR(100) NULL,
    block               NVARCHAR(40)  NULL,
    lot                 NVARCHAR(40)  NULL,
    bylot_cnt           INT           NULL,
    vl_rat_estm_tot_area DECIMAL(19,5) NULL,
    tot_pkng_cnt        INT           NULL,
    indr_mech_utcnt INT NULL, indr_mech_area DECIMAL(19,5) NULL,
    oudr_mech_utcnt INT NULL, oudr_mech_area DECIMAL(19,5) NULL,
    indr_auto_utcnt INT NULL, indr_auto_area DECIMAL(19,5) NULL,
    oudr_auto_utcnt INT NULL, oudr_auto_area DECIMAL(19,5) NULL,
    engr_grade NVARCHAR(40) NULL, engr_rat DECIMAL(13,3) NULL, engr_epi DECIMAL(13,3) NULL,
    gn_bld_grade NVARCHAR(40) NULL, gn_bld_cert DECIMAL(13,3) NULL,
    itg_bld_grade NVARCHAR(40) NULL, itg_bld_cert DECIMAL(13,3) NULL,
    pmsno_year CHAR(4) NULL, pmsno_kik_cd VARCHAR(20) NULL, pmsno_kik_nm NVARCHAR(80) NULL,
    pmsno_gb_cd VARCHAR(10) NULL, pmsno_gb_nm NVARCHAR(80) NULL;
GO

/* ============================================================
   E) gold 재구축 - 단지코드를 INT auto increment 로
   ============================================================ */
IF OBJECT_ID('gold.v_complex_360') IS NOT NULL DROP VIEW gold.v_complex_360;
IF OBJECT_ID('gold.v_link_gap')    IS NOT NULL DROP VIEW gold.v_link_gap;
IF OBJECT_ID('gold.usp_build_complexes')  IS NOT NULL DROP PROCEDURE gold.usp_build_complexes;
IF OBJECT_ID('gold.usp_resolve_complex')  IS NOT NULL DROP PROCEDURE gold.usp_resolve_complex;
IF OBJECT_ID('gold.complex_pnu')      IS NOT NULL DROP TABLE gold.complex_pnu;
IF OBJECT_ID('gold.complex_bld')      IS NOT NULL DROP TABLE gold.complex_bld;
IF OBJECT_ID('gold.complex_identity') IS NOT NULL DROP TABLE gold.complex_identity;
IF OBJECT_ID('gold.complex')          IS NOT NULL DROP TABLE gold.complex;
IF EXISTS (SELECT 1 FROM sys.sequences WHERE name='seq_complex') DROP SEQUENCE gold.seq_complex;
GO

CREATE TABLE gold.complex (
    complex_id       INT IDENTITY(1,1) NOT NULL,   -- 1, 2, 3 ...
    root_bldrgst_pk  VARCHAR(50)   NULL,           -- 단지의 뿌리 PK
    complex_nm       NVARCHAR(200) NULL,
    rep_pnu          CHAR(19)      NULL,
    rep_plat_plc     NVARCHAR(300) NULL,
    rep_road_addr    NVARCHAR(400) NULL,
    sigungu_cd       CHAR(5)       NULL,
    bjdong_cd        CHAR(5)       NULL,
    has_recap        BIT           NOT NULL DEFAULT 0,  -- 총괄표제부 보유 여부
    dong_cnt         INT           NULL,
    pnu_cnt          INT           NULL,
    hhld_cnt_sum     INT           NULL,
    tot_area_sum     DECIMAL(19,5) NULL,
    oldest_use_apr   CHAR(8)       NULL,
    latest_use_apr   CHAR(8)       NULL,
    grouping_rule    VARCHAR(30)   NULL,           -- RECAP | STANDALONE
    is_active        BIT           NOT NULL DEFAULT 1,
    created_at       DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    updated_at       DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_complex PRIMARY KEY CLUSTERED (complex_id)
);
GO
CREATE INDEX ix_complex_sgg  ON gold.complex (sigungu_cd, bjdong_cd);
CREATE INDEX ix_complex_root ON gold.complex (root_bldrgst_pk);
GO

/* 단지 식별 근거 - 재적재 시 같은 단지로 다시 찾아가게 하는 장치 */
CREATE TABLE gold.complex_identity (
    identity_sk      BIGINT IDENTITY(1,1) NOT NULL,
    complex_id       INT           NOT NULL,
    identity_type    VARCHAR(20)   NOT NULL,   -- ROOT_PK (현재 유일) | MANUAL | EXT_*
    identity_val     VARCHAR(100)  NOT NULL,
    is_primary       BIT           NOT NULL DEFAULT 0,
    created_at       DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_complex_identity PRIMARY KEY CLUSTERED (identity_sk),
    CONSTRAINT fk_identity_complex FOREIGN KEY (complex_id) REFERENCES gold.complex(complex_id)
);
GO
CREATE UNIQUE INDEX uq_complex_identity ON gold.complex_identity (identity_type, identity_val);
GO

CREATE TABLE gold.complex_bld (
    complex_id       INT           NOT NULL,
    mgm_bldrgst_pk   VARCHAR(50)   NOT NULL,
    regstr_kind_cd   VARCHAR(2)    NULL,
    is_recap         BIT           NOT NULL DEFAULT 0,   -- 이 레코드가 총괄표제부인가
    link_rule        VARCHAR(30)   NULL,
    linked_at        DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_complex_bld PRIMARY KEY CLUSTERED (complex_id, mgm_bldrgst_pk),
    CONSTRAINT fk_cbld_complex FOREIGN KEY (complex_id) REFERENCES gold.complex(complex_id)
);
GO
/* 한 대장이 두 단지에 속하면 집계가 이중계상된다 */
CREATE UNIQUE INDEX uq_complex_bld_once ON gold.complex_bld (mgm_bldrgst_pk);
GO

CREATE TABLE gold.complex_pnu (
    complex_id       INT           NOT NULL,
    pnu              CHAR(19)      NOT NULL,
    pnu_role         VARCHAR(20)   NULL,       -- MAIN | ATTACHED
    is_representative BIT          NOT NULL DEFAULT 0,
    linked_at        DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_complex_pnu PRIMARY KEY CLUSTERED (complex_id, pnu),
    CONSTRAINT fk_cpnu_complex FOREIGN KEY (complex_id) REFERENCES gold.complex(complex_id)
);
GO
CREATE INDEX ix_complex_pnu_rev ON gold.complex_pnu (pnu) INCLUDE (complex_id, pnu_role);
GO

/* ============================================================
   F) 단지코드 발급 (멱등)
   ============================================================ */
CREATE PROCEDURE gold.usp_resolve_complex
    @identity_type  VARCHAR(20),
    @identity_val   VARCHAR(100),
    @complex_nm     NVARCHAR(200) = NULL,
    @sigungu_cd     CHAR(5)       = NULL,
    @bjdong_cd      CHAR(5)       = NULL,
    @grouping_rule  VARCHAR(30)   = NULL,
    @root_pk        VARCHAR(50)   = NULL,
    @complex_id     INT           OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /* ★ OUTPUT 변수는 호출자의 직전 값을 들고 들어온다.
       SELECT @x = ... 는 행이 없으면 변수를 그대로 둔다(NULL 로 만들지 않는다).
       초기화하지 않으면 두 번째 호출부터 직전 단지를 재사용해버린다. */
    SET @complex_id = NULL;

    SELECT @complex_id = complex_id
    FROM gold.complex_identity
    WHERE identity_type = @identity_type AND identity_val = @identity_val;

    IF @complex_id IS NOT NULL
    BEGIN
        UPDATE gold.complex
           SET complex_nm = COALESCE(@complex_nm, complex_nm),
               updated_at = SYSDATETIME()
         WHERE complex_id = @complex_id;
        RETURN;
    END

    BEGIN TRAN;
        INSERT INTO gold.complex (root_bldrgst_pk, complex_nm, sigungu_cd, bjdong_cd, grouping_rule)
        VALUES (@root_pk, @complex_nm, @sigungu_cd, @bjdong_cd, @grouping_rule);
        SET @complex_id = CAST(SCOPE_IDENTITY() AS INT);

        INSERT INTO gold.complex_identity (complex_id, identity_type, identity_val, is_primary)
        VALUES (@complex_id, @identity_type, @identity_val, 1);
    COMMIT;
END
GO

/* ============================================================
   G) 단지 구성 - 기본개요 기준
       root_bldrgst_pk = 부모가 있으면 부모, 없으면 자기 자신
       전유부(4)는 호 단위이므로 단지 구성에서 제외
   ============================================================ */
CREATE PROCEDURE gold.usp_build_complexes
    @sigungu_cd CHAR(5) = NULL,
    @bjdong_cd  CHAR(5) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /* ---- root_bldrgst_pk 채우기 ('0'/공백/NULL = 부모 없음) ---- */
    UPDATE silver.bld_basis_outline
       SET root_bldrgst_pk =
           CASE WHEN NULLIF(LTRIM(RTRIM(ISNULL(mgm_up_bldrgst_pk,''))),'') IS NULL
                  OR LTRIM(RTRIM(mgm_up_bldrgst_pk)) = '0'
                THEN mgm_bldrgst_pk
                ELSE LTRIM(RTRIM(mgm_up_bldrgst_pk))
           END
     WHERE is_current = 1
       AND (@sigungu_cd IS NULL OR sigungu_cd = @sigungu_cd)
       AND (@bjdong_cd  IS NULL OR bjdong_cd  = @bjdong_cd);

    /* ---- 단지 발급 ---- */
    DECLARE @id INT, @iv VARCHAR(100), @nm NVARCHAR(200),
            @sgg CHAR(5), @bjd CHAR(5), @rule VARCHAR(30);

    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT b.root_bldrgst_pk,
               /* 단지명: 총괄표제부 이름 > 아무 구성원의 이름.
                  bldNm 이 73% 비어 있으므로 MAX(그냥 있는 것) 로 대체 */
               MAX(CASE WHEN b.regstr_kind_cd = '1' THEN b.bld_nm END),
               MAX(b.sigungu_cd), MAX(b.bjdong_cd),
               CASE WHEN MAX(CASE WHEN b.regstr_kind_cd='1' THEN 1 ELSE 0 END) = 1
                    THEN 'RECAP' ELSE 'STANDALONE' END
        FROM silver.bld_basis_outline b
        WHERE b.is_current = 1
          AND b.regstr_kind_cd IN ('1','2','3')      -- 전유부 제외
          AND b.root_bldrgst_pk IS NOT NULL
          AND (@sigungu_cd IS NULL OR b.sigungu_cd = @sigungu_cd)
          AND (@bjdong_cd  IS NULL OR b.bjdong_cd  = @bjdong_cd)
        GROUP BY b.root_bldrgst_pk;

    OPEN cur;
    FETCH NEXT FROM cur INTO @iv, @nm, @sgg, @bjd, @rule;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC gold.usp_resolve_complex 'ROOT_PK', @iv, @nm, @sgg, @bjd, @rule, @iv,
             @complex_id = @id OUTPUT;
        FETCH NEXT FROM cur INTO @iv, @nm, @sgg, @bjd, @rule;
    END
    CLOSE cur; DEALLOCATE cur;

    /* ---- 단지 <-> 대장 매핑 ---- */
    MERGE gold.complex_bld AS tgt
    USING (
        SELECT ci.complex_id, b.mgm_bldrgst_pk, b.regstr_kind_cd,
               CASE WHEN b.regstr_kind_cd = '1' THEN 1 ELSE 0 END AS is_recap,
               CASE WHEN b.mgm_bldrgst_pk = b.root_bldrgst_pk
                    THEN 'ROOT' ELSE 'CHILD' END AS link_rule
        FROM silver.bld_basis_outline b
        JOIN gold.complex_identity ci
          ON ci.identity_type = 'ROOT_PK' AND ci.identity_val = b.root_bldrgst_pk
        WHERE b.is_current = 1 AND b.regstr_kind_cd IN ('1','2','3')
          AND (@sigungu_cd IS NULL OR b.sigungu_cd = @sigungu_cd)
          AND (@bjdong_cd  IS NULL OR b.bjdong_cd  = @bjdong_cd)
    ) AS src
       ON tgt.mgm_bldrgst_pk = src.mgm_bldrgst_pk
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (complex_id, mgm_bldrgst_pk, regstr_kind_cd, is_recap, link_rule)
        VALUES (src.complex_id, src.mgm_bldrgst_pk, src.regstr_kind_cd, src.is_recap, src.link_rule);

    /* ---- 단지 <-> 필지 (기본개요 대지 + 부속지번 합집합) ---- */
    MERGE gold.complex_pnu AS tgt
    USING (
        /* (complex_id, pnu) 로 묶는다. 한 PNU 가 대지이면서 동시에
           다른 동의 부속지번일 수 있어, 묶지 않으면 PK 가 터진다.
           MAX('MAIN','ATTACHED') = 'MAIN' -> 대지 역할 우선. */
        SELECT cb.complex_id, x.pnu, MAX(x.pnu_role) AS pnu_role
        FROM gold.complex_bld cb
        CROSS APPLY (
            SELECT b.pnu, 'MAIN' AS pnu_role
            FROM silver.bld_basis_outline b
            WHERE b.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND b.is_current = 1 AND b.pnu IS NOT NULL
            UNION ALL
            SELECT a.atch_pnu, 'ATTACHED'
            FROM silver.bld_atch_jibun a
            WHERE a.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND a.is_current = 1 AND a.atch_pnu IS NOT NULL
        ) x
        GROUP BY cb.complex_id, x.pnu
    ) AS src
       ON tgt.complex_id = src.complex_id AND tgt.pnu = src.pnu
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (complex_id, pnu, pnu_role) VALUES (src.complex_id, src.pnu, src.pnu_role);

    /* ---- 요약값 재계산 ---- */
    WITH agg AS (
        SELECT cb.complex_id,
               SUM(CASE WHEN cb.regstr_kind_cd IN ('2','3') THEN 1 ELSE 0 END) AS dong_cnt,
               MAX(CASE WHEN cb.is_recap = 1 THEN 1 ELSE 0 END)                AS has_recap
        FROM gold.complex_bld cb GROUP BY cb.complex_id
    ), tagg AS (
        SELECT cb.complex_id,
               SUM(t.hhld_cnt) AS hhld_sum, SUM(t.tot_area) AS area_sum,
               MIN(NULLIF(t.use_apr_day,'')) AS min_apr, MAX(NULLIF(t.use_apr_day,'')) AS max_apr
        FROM gold.complex_bld cb
        JOIN silver.bld_title t ON t.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND t.is_current = 1
        GROUP BY cb.complex_id
    ), pnuagg AS (
        SELECT complex_id, COUNT(*) AS pnu_cnt FROM gold.complex_pnu GROUP BY complex_id
    ), rep AS (
        /* 대표 = 총괄표제부 우선, 없으면 연면적 최대 */
        SELECT cb.complex_id, b.pnu, b.plat_plc, b.new_plat_plc,
               ROW_NUMBER() OVER (PARTITION BY cb.complex_id
                   ORDER BY cb.is_recap DESC, ISNULL(t.tot_area,0) DESC, b.mgm_bldrgst_pk) AS rn
        FROM gold.complex_bld cb
        JOIN silver.bld_basis_outline b ON b.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND b.is_current = 1
        LEFT JOIN silver.bld_title t    ON t.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND t.is_current = 1
    )
    UPDATE c
       SET c.dong_cnt       = a.dong_cnt,
           c.has_recap      = a.has_recap,
           c.pnu_cnt        = p.pnu_cnt,
           c.hhld_cnt_sum   = tg.hhld_sum,
           c.tot_area_sum   = tg.area_sum,
           c.oldest_use_apr = tg.min_apr,
           c.latest_use_apr = tg.max_apr,
           c.rep_pnu        = r.pnu,
           c.rep_plat_plc   = r.plat_plc,
           c.rep_road_addr  = r.new_plat_plc,
           c.updated_at     = SYSDATETIME()
      FROM gold.complex c
      JOIN agg a         ON a.complex_id  = c.complex_id
      LEFT JOIN tagg tg  ON tg.complex_id = c.complex_id
      LEFT JOIN pnuagg p ON p.complex_id  = c.complex_id
      LEFT JOIN rep r    ON r.complex_id  = c.complex_id AND r.rn = 1;

    UPDATE cp SET is_representative = 1
      FROM gold.complex_pnu cp
      JOIN gold.complex c ON c.complex_id = cp.complex_id AND c.rep_pnu = cp.pnu;

    /* 단지명이 비면 대표 주소로 대체 (bldNm 73% 결손 대응) */
    UPDATE gold.complex
       SET complex_nm = rep_plat_plc
     WHERE complex_nm IS NULL AND rep_plat_plc IS NOT NULL;
END
GO

/* ============================================================
   H) 뷰 재생성
   ============================================================ */
CREATE VIEW gold.v_complex_360
AS
SELECT
    c.complex_id,
    c.complex_nm,
    c.root_bldrgst_pk,
    c.grouping_rule,
    c.has_recap,
    c.sigungu_cd,
    l.full_nm                       AS lawd_full_nm,
    c.rep_pnu,
    meta.fn_pnu_to_jibun(c.rep_pnu) AS rep_jibun,
    c.rep_plat_plc,
    c.rep_road_addr,
    c.dong_cnt,
    c.pnu_cnt,
    c.hhld_cnt_sum,
    c.tot_area_sum,
    c.oldest_use_apr,
    c.latest_use_apr,
    lnd.land_linked      AS land_linked_cnt,
    rd.road_linked       AS road_linked_cnt,
    reg.reg_linked       AS registry_linked_cnt,
    CAST(CASE WHEN c.pnu_cnt > 0
              THEN 1.0 * ISNULL(lnd.land_linked,0) / c.pnu_cnt ELSE 0 END AS DECIMAL(5,4)) AS land_coverage,
    CAST(CASE WHEN c.dong_cnt > 0
              THEN 1.0 * ISNULL(rd.road_linked,0) / c.dong_cnt ELSE 0 END AS DECIMAL(5,4)) AS road_coverage,
    lnd.pblntf_pclnd_avg,
    lnd.lndpcl_ar_sum
FROM gold.complex c
LEFT JOIN meta.lawd_code l ON l.lawd_cd = LEFT(c.rep_pnu,10)
LEFT JOIN (
    SELECT cp.complex_id,
           COUNT(lc.pnu)        AS land_linked,
           AVG(lc.pblntf_pclnd) AS pblntf_pclnd_avg,
           SUM(lc.lndpcl_ar)    AS lndpcl_ar_sum
    FROM gold.complex_pnu cp
    LEFT JOIN silver.land_char lc ON lc.pnu = cp.pnu AND lc.is_current = 1
    GROUP BY cp.complex_id
) lnd ON lnd.complex_id = c.complex_id
LEFT JOIN (
    /* 분자는 "도로명이 붙은 대장 수". 건물관리번호로 세면 안 된다 -
       여러 동이 같은 도로명주소를 공유하는 것이 정상이다. */
    SELECT cb.complex_id, COUNT(DISTINCT cb.mgm_bldrgst_pk) AS road_linked
    FROM gold.complex_bld cb
    JOIN silver.bld_basis_outline b ON b.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND b.is_current = 1
    WHERE cb.regstr_kind_cd IN ('2','3')
      AND EXISTS (
        SELECT 1 FROM silver.road_addr ra
        WHERE ra.road_cd = b.na_road_cd AND ra.ugrnd_yn = b.na_ugrnd_cd
          AND ra.bld_main_no = b.na_main_bun
          AND ISNULL(ra.bld_sub_no,0) = ISNULL(b.na_sub_bun,0)
          AND ra.is_current = 1)
    GROUP BY cb.complex_id
) rd ON rd.complex_id = c.complex_id
LEFT JOIN (
    SELECT cp.complex_id, COUNT(rp.reg_sk) AS reg_linked
    FROM gold.complex_pnu cp
    LEFT JOIN silver.registry_property rp
           ON rp.match_pnu = cp.pnu AND rp.is_current = 1 AND rp.match_status = 'MATCHED'
    GROUP BY cp.complex_id
) reg ON reg.complex_id = c.complex_id;
GO

CREATE VIEW gold.v_link_gap
AS
SELECT 'LAND_MISSING' AS gap_type, cp.complex_id, cp.pnu AS key_val,
       CAST(NULL AS NVARCHAR(200)) AS note
FROM gold.complex_pnu cp
LEFT JOIN silver.land_char lc ON lc.pnu = cp.pnu AND lc.is_current = 1
WHERE lc.pnu IS NULL
UNION ALL
SELECT 'ROADKEY_NULL', cb.complex_id, b.mgm_bldrgst_pk,
       N'na_road_cd=' + ISNULL(b.na_road_cd,N'<null>')
FROM gold.complex_bld cb
JOIN silver.bld_basis_outline b ON b.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND b.is_current = 1
WHERE cb.regstr_kind_cd IN ('2','3') AND (b.na_road_cd IS NULL OR b.na_main_bun IS NULL)
UNION ALL
SELECT 'PNU_NULL', cb.complex_id, b.mgm_bldrgst_pk,
       N'sgg=' + ISNULL(b.sigungu_cd,N'?') + N' bun=' + ISNULL(b.bun,N'?')
FROM gold.complex_bld cb
JOIN silver.bld_basis_outline b ON b.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND b.is_current = 1
WHERE b.pnu IS NULL
UNION ALL
/* 기본개요에는 있는데 표제부/일반건축물 상세가 안 들어온 경우 */
SELECT 'TITLE_MISSING', cb.complex_id, cb.mgm_bldrgst_pk, NULL
FROM gold.complex_bld cb
LEFT JOIN silver.bld_title t ON t.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND t.is_current = 1
WHERE cb.regstr_kind_cd IN ('2','3') AND t.mgm_bldrgst_pk IS NULL;
GO

PRINT '05_revise done.';
GO
