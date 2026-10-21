SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* ============================================================
   Teomoony - 03_gold : 단지코드 허브

   ★ 설계 판단 : 자체발급 단지코드를 PNU 기반으로 만들면 안 된다.
     이유 - 지번은 분할/합병/행정구역 개편으로 바뀐다. PNU를 코드에
            박아 넣으면 그 순간 단지의 정체성이 깨지고, 과거 데이터와
            연결이 끊긴다.
     결론 - 단지코드는 의미 없는 surrogate 로 두고,
            "무엇을 근거로 이 단지를 식별했는지"를 별도 테이블
            (complex_identity) 에 남긴다.
            재적재할 때 identity 로 기존 단지를 다시 찾아가므로
            코드가 재현된다. 이 장치가 없으면 적재할 때마다 새 코드가
            발급되어 단지코드가 쓸모없어진다.
   ============================================================ */
USE Teomoony;
GO

IF NOT EXISTS (SELECT 1 FROM sys.sequences WHERE name='seq_complex')
CREATE SEQUENCE gold.seq_complex AS BIGINT START WITH 1 INCREMENT BY 1;
GO

/* ------------------------------------------------------------
   단지 마스터
   ------------------------------------------------------------ */
IF OBJECT_ID('gold.complex') IS NULL
CREATE TABLE gold.complex (
    complex_cd       CHAR(13)      NOT NULL,   -- 'TM' + 11자리 (자체발급)
    complex_nm       NVARCHAR(200) NULL,
    /* 대표 위치 - 표시용. 조인 키로 쓰지 말 것(대표지번은 바뀐다) */
    rep_pnu          CHAR(19)      NULL,
    rep_plat_plc     NVARCHAR(300) NULL,
    rep_road_addr    NVARCHAR(400) NULL,
    sigungu_cd       CHAR(5)       NULL,
    /* 단지 구성 요약 */
    dong_cnt         INT           NULL,       -- 동 수
    pnu_cnt          INT           NULL,       -- 걸친 필지 수
    hhld_cnt_sum     INT           NULL,
    tot_area_sum     DECIMAL(19,5) NULL,
    plat_area_sum    DECIMAL(19,5) NULL,
    oldest_use_apr   CHAR(8)       NULL,
    latest_use_apr   CHAR(8)       NULL,
    /* 운영 */
    grouping_rule    VARCHAR(30)   NULL,       -- 어떤 규칙으로 묶였는지
    is_active        BIT           NOT NULL DEFAULT 1,
    created_at       DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    updated_at       DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_complex PRIMARY KEY CLUSTERED (complex_cd)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_complex_sgg')
CREATE INDEX ix_complex_sgg ON gold.complex (sigungu_cd) INCLUDE (complex_nm);
GO

/* ------------------------------------------------------------
   ★ 단지 식별 근거 - 단지코드 재현의 핵심
      같은 단지를 재적재할 때 여기서 기존 코드를 찾아간다.
   ------------------------------------------------------------ */
IF OBJECT_ID('gold.complex_identity') IS NULL
CREATE TABLE gold.complex_identity (
    identity_sk      BIGINT IDENTITY(1,1) NOT NULL,
    complex_cd       CHAR(13)      NOT NULL,
    identity_type    VARCHAR(20)   NOT NULL,
        /* RECAP_PK     : 총괄표제부 PK (1순위, 가장 안정적)
           BLD_PK       : 표제부 PK (총괄 없는 단독 건물)
           PNU          : 구성 필지 (보조 - 지번 변경에 취약)
           EXT_KAPT     : 외부 공동주택 단지코드 (나중에 붙일 때)
           MANUAL       : 사람이 지정                                */
    identity_val     VARCHAR(100)  NOT NULL,
    is_primary       BIT           NOT NULL DEFAULT 0,
    created_at       DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_complex_identity PRIMARY KEY CLUSTERED (identity_sk),
    CONSTRAINT fk_identity_complex FOREIGN KEY (complex_cd) REFERENCES gold.complex(complex_cd)
);
GO
/* 같은 식별자가 두 단지에 달리는 것을 DB가 막는다 */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='uq_complex_identity')
CREATE UNIQUE INDEX uq_complex_identity ON gold.complex_identity (identity_type, identity_val);
GO

/* ------------------------------------------------------------
   단지 <-> 건축물대장(동)   1:n
   ------------------------------------------------------------ */
IF OBJECT_ID('gold.complex_bld') IS NULL
CREATE TABLE gold.complex_bld (
    complex_cd       CHAR(13)      NOT NULL,
    mgm_bldrgst_pk   VARCHAR(50)   NOT NULL,
    link_rule        VARCHAR(30)   NULL,       -- RECAP_CHILD | SAME_PNU | MANUAL
    is_main_bld      BIT           NOT NULL DEFAULT 0,
    linked_at        DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_complex_bld PRIMARY KEY CLUSTERED (complex_cd, mgm_bldrgst_pk),
    CONSTRAINT fk_cbld_complex FOREIGN KEY (complex_cd) REFERENCES gold.complex(complex_cd)
);
GO
/* 한 동이 두 단지에 속하면 집계가 이중계상된다 - 금지 */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='uq_complex_bld_once')
CREATE UNIQUE INDEX uq_complex_bld_once ON gold.complex_bld (mgm_bldrgst_pk);
GO

/* ------------------------------------------------------------
   단지 <-> 토지(필지)   1:n
   대지 + 부속지번을 합집합으로 담는다.
   ------------------------------------------------------------ */
IF OBJECT_ID('gold.complex_pnu') IS NULL
CREATE TABLE gold.complex_pnu (
    complex_cd       CHAR(13)      NOT NULL,
    pnu              CHAR(19)      NOT NULL,
    pnu_role         VARCHAR(20)   NULL,       -- MAIN(대지) | ATTACHED(부속지번)
    is_representative BIT          NOT NULL DEFAULT 0,
    linked_at        DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_complex_pnu PRIMARY KEY CLUSTERED (complex_cd, pnu),
    CONSTRAINT fk_cpnu_complex FOREIGN KEY (complex_cd) REFERENCES gold.complex(complex_cd)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_complex_pnu_rev')
CREATE INDEX ix_complex_pnu_rev ON gold.complex_pnu (pnu) INCLUDE (complex_cd, pnu_role);
GO

/* ============================================================
   단지코드 발급/해석 프로시저
   identity 로 먼저 찾고, 없으면 새로 발급한다 (idempotent)
   ============================================================ */
IF OBJECT_ID('gold.usp_resolve_complex') IS NOT NULL DROP PROCEDURE gold.usp_resolve_complex;
GO
CREATE PROCEDURE gold.usp_resolve_complex
    @identity_type  VARCHAR(20),
    @identity_val   VARCHAR(100),
    @complex_nm     NVARCHAR(200) = NULL,
    @sigungu_cd     CHAR(5)       = NULL,
    @grouping_rule  VARCHAR(30)   = NULL,
    @complex_cd     CHAR(13)      OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /* ★ 필수 : OUTPUT 변수는 호출자의 직전 값을 들고 들어온다.
       SELECT @x = ... 는 행이 없으면 변수를 "그대로 둔다"(NULL 로 만들지 않음).
       초기화하지 않으면 두 번째 호출부터 직전 단지코드를 재사용해버린다. */
    SET @complex_cd = NULL;

    /* 1) 이미 있으면 그 코드를 그대로 돌려준다 */
    SELECT @complex_cd = complex_cd
    FROM gold.complex_identity
    WHERE identity_type = @identity_type AND identity_val = @identity_val;

    IF @complex_cd IS NOT NULL
    BEGIN
        UPDATE gold.complex
           SET complex_nm = COALESCE(@complex_nm, complex_nm),
               updated_at = SYSDATETIME()
         WHERE complex_cd = @complex_cd;
        RETURN;
    END

    /* 2) 신규 발급 */
    BEGIN TRAN;
        DECLARE @seq BIGINT = NEXT VALUE FOR gold.seq_complex;
        SET @complex_cd = 'TM' + RIGHT('00000000000' + CAST(@seq AS VARCHAR(20)), 11);

        INSERT INTO gold.complex (complex_cd, complex_nm, sigungu_cd, grouping_rule)
        VALUES (@complex_cd, @complex_nm, @sigungu_cd, @grouping_rule);

        INSERT INTO gold.complex_identity (complex_cd, identity_type, identity_val, is_primary)
        VALUES (@complex_cd, @identity_type, @identity_val, 1);
    COMMIT;
END
GO

/* ============================================================
   단지 자동 구성 (건축물대장 기준)
     1순위 : 총괄표제부 PK(mgm_up_bldrgst_pk) 가 있으면 그것이 단지
     2순위 : 총괄이 없으면 표제부 자신을 단독 단지로
   ============================================================ */
IF OBJECT_ID('gold.usp_build_complexes') IS NOT NULL DROP PROCEDURE gold.usp_build_complexes;
GO
CREATE PROCEDURE gold.usp_build_complexes
    @sigungu_cd CHAR(5) = NULL          -- NULL 이면 전체
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @cd CHAR(13), @it VARCHAR(20), @iv VARCHAR(100),
            @nm NVARCHAR(200), @sgg CHAR(5), @rule VARCHAR(30);

    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        /* 총괄표제부가 있는 묶음 */
        SELECT 'RECAP_PK',
               t.mgm_up_bldrgst_pk,
               MAX(COALESCE(r.bld_nm, t.bld_nm)),
               MAX(t.sigungu_cd),
               'RECAP'
        FROM silver.bld_title t
        LEFT JOIN silver.bld_recap_title r
               ON r.mgm_bldrgst_pk = t.mgm_up_bldrgst_pk AND r.is_current = 1
        WHERE t.is_current = 1
          AND NULLIF(LTRIM(RTRIM(t.mgm_up_bldrgst_pk)),'') IS NOT NULL
          AND (@sigungu_cd IS NULL OR t.sigungu_cd = @sigungu_cd)
        GROUP BY t.mgm_up_bldrgst_pk
        UNION ALL
        /* 총괄 없는 단독 */
        SELECT 'BLD_PK',
               t.mgm_bldrgst_pk,
               t.bld_nm,
               t.sigungu_cd,
               'STANDALONE'
        FROM silver.bld_title t
        WHERE t.is_current = 1
          AND NULLIF(LTRIM(RTRIM(t.mgm_up_bldrgst_pk)),'') IS NULL
          AND (@sigungu_cd IS NULL OR t.sigungu_cd = @sigungu_cd);

    OPEN cur;
    FETCH NEXT FROM cur INTO @it, @iv, @nm, @sgg, @rule;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC gold.usp_resolve_complex @it, @iv, @nm, @sgg, @rule, @complex_cd = @cd OUTPUT;
        FETCH NEXT FROM cur INTO @it, @iv, @nm, @sgg, @rule;
    END
    CLOSE cur; DEALLOCATE cur;

    /* ---- 단지 <-> 동 매핑 ---- */
    MERGE gold.complex_bld AS tgt
    USING (
        SELECT ci.complex_cd, t.mgm_bldrgst_pk,
               CASE WHEN ci.identity_type='RECAP_PK' THEN 'RECAP_CHILD' ELSE 'STANDALONE' END AS link_rule
        FROM silver.bld_title t
        JOIN gold.complex_identity ci
          ON (ci.identity_type='RECAP_PK' AND ci.identity_val = t.mgm_up_bldrgst_pk)
          OR (ci.identity_type='BLD_PK'  AND ci.identity_val = t.mgm_bldrgst_pk
              AND NULLIF(LTRIM(RTRIM(t.mgm_up_bldrgst_pk)),'') IS NULL)
        WHERE t.is_current = 1
          AND (@sigungu_cd IS NULL OR t.sigungu_cd = @sigungu_cd)
    ) AS src
       ON tgt.mgm_bldrgst_pk = src.mgm_bldrgst_pk
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (complex_cd, mgm_bldrgst_pk, link_rule)
        VALUES (src.complex_cd, src.mgm_bldrgst_pk, src.link_rule);

    /* ---- 단지 <-> 필지 매핑 (대지 + 부속지번 합집합) ---- */
    MERGE gold.complex_pnu AS tgt
    USING (
        SELECT DISTINCT cb.complex_cd, x.pnu, x.pnu_role
        FROM gold.complex_bld cb
        CROSS APPLY (
            SELECT t.pnu, 'MAIN' AS pnu_role
            FROM silver.bld_title t
            WHERE t.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND t.is_current = 1 AND t.pnu IS NOT NULL
            UNION
            SELECT a.atch_pnu, 'ATTACHED'
            FROM silver.bld_atch_jibun a
            WHERE a.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND a.is_current = 1 AND a.atch_pnu IS NOT NULL
        ) x
    ) AS src
       ON tgt.complex_cd = src.complex_cd AND tgt.pnu = src.pnu
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (complex_cd, pnu, pnu_role) VALUES (src.complex_cd, src.pnu, src.pnu_role);

    /* ---- 단지 요약값 재계산 ---- */
    WITH agg AS (
        SELECT cb.complex_cd,
               COUNT(DISTINCT cb.mgm_bldrgst_pk) AS dong_cnt,
               SUM(t.hhld_cnt)                   AS hhld_sum,
               SUM(t.tot_area)                   AS area_sum,
               MIN(NULLIF(t.use_apr_day,''))     AS min_apr,
               MAX(NULLIF(t.use_apr_day,''))     AS max_apr,
               MAX(t.sigungu_cd)                 AS sgg
        FROM gold.complex_bld cb
        JOIN silver.bld_title t ON t.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND t.is_current = 1
        GROUP BY cb.complex_cd
    ), pnuagg AS (
        SELECT complex_cd, COUNT(*) AS pnu_cnt FROM gold.complex_pnu GROUP BY complex_cd
    ), rep AS (
        /* 대표지번 = 연면적 최대 동의 대지 */
        SELECT cb.complex_cd, t.pnu, t.plat_plc, t.new_plat_plc,
               ROW_NUMBER() OVER (PARTITION BY cb.complex_cd
                                  ORDER BY ISNULL(t.tot_area,0) DESC, t.mgm_bldrgst_pk) AS rn
        FROM gold.complex_bld cb
        JOIN silver.bld_title t ON t.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND t.is_current = 1
    )
    UPDATE c
       SET c.dong_cnt       = a.dong_cnt,
           c.pnu_cnt        = p.pnu_cnt,
           c.hhld_cnt_sum   = a.hhld_sum,
           c.tot_area_sum   = a.area_sum,
           c.oldest_use_apr = a.min_apr,
           c.latest_use_apr = a.max_apr,
           c.sigungu_cd     = COALESCE(c.sigungu_cd, a.sgg),
           c.rep_pnu        = r.pnu,
           c.rep_plat_plc   = r.plat_plc,
           c.rep_road_addr  = r.new_plat_plc,
           c.updated_at     = SYSDATETIME()
      FROM gold.complex c
      JOIN agg a    ON a.complex_cd = c.complex_cd
      LEFT JOIN pnuagg p ON p.complex_cd = c.complex_cd
      LEFT JOIN rep r    ON r.complex_cd = c.complex_cd AND r.rn = 1;

    /* 대표 필지 플래그 */
    UPDATE cp SET is_representative = 1
      FROM gold.complex_pnu cp
      JOIN gold.complex c ON c.complex_cd = cp.complex_cd AND c.rep_pnu = cp.pnu;
END
GO

/* ============================================================
   단지코드 하나로 전부 보는 뷰
   ============================================================ */
IF OBJECT_ID('gold.v_complex_360') IS NOT NULL DROP VIEW gold.v_complex_360;
GO
CREATE VIEW gold.v_complex_360
AS
SELECT
    c.complex_cd,
    c.complex_nm,
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
    c.grouping_rule,
    /* ---- 축별 연계 충족 여부 (파이프라인 품질 지표) ---- */
    bld.bld_linked       AS bld_cnt,
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
LEFT JOIN meta.lawd_code l
       ON l.lawd_cd = LEFT(c.rep_pnu,10)
LEFT JOIN (
    SELECT complex_cd, COUNT(*) AS bld_linked FROM gold.complex_bld GROUP BY complex_cd
) bld ON bld.complex_cd = c.complex_cd
LEFT JOIN (
    SELECT cp.complex_cd,
           COUNT(lc.pnu)            AS land_linked,
           AVG(lc.pblntf_pclnd)     AS pblntf_pclnd_avg,
           SUM(lc.lndpcl_ar)        AS lndpcl_ar_sum
    FROM gold.complex_pnu cp
    LEFT JOIN silver.land_char lc ON lc.pnu = cp.pnu AND lc.is_current = 1
    GROUP BY cp.complex_cd
) lnd ON lnd.complex_cd = c.complex_cd
LEFT JOIN (
    /* ★ 분자는 "도로명이 붙은 동 수". 건물관리번호로 세면 안 된다 -
       여러 동이 같은 도로명주소를 공유하는 것이 정상이므로
       DISTINCT bld_mgt_no 로 세면 연계 성공을 실패로 오판한다. */
    SELECT cb.complex_cd, COUNT(DISTINCT cb.mgm_bldrgst_pk) AS road_linked
    FROM gold.complex_bld cb
    JOIN silver.bld_title t ON t.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND t.is_current = 1
    WHERE EXISTS (
        SELECT 1 FROM silver.road_addr ra
        WHERE ra.road_cd     = t.na_road_cd
          AND ra.ugrnd_yn    = t.na_ugrnd_cd
          AND ra.bld_main_no = t.na_main_bun
          AND ISNULL(ra.bld_sub_no,0) = ISNULL(t.na_sub_bun,0)
          AND ra.is_current  = 1
    )
    GROUP BY cb.complex_cd
) rd ON rd.complex_cd = c.complex_cd
LEFT JOIN (
    SELECT cp.complex_cd, COUNT(rp.reg_sk) AS reg_linked
    FROM gold.complex_pnu cp
    LEFT JOIN silver.registry_property rp
           ON rp.match_pnu = cp.pnu AND rp.is_current = 1 AND rp.match_status = 'MATCHED'
    GROUP BY cp.complex_cd
) reg ON reg.complex_cd = c.complex_cd;
GO

/* ============================================================
   현행화 모니터링
   ============================================================ */
IF OBJECT_ID('gold.v_staleness') IS NOT NULL DROP VIEW gold.v_staleness;
GO
CREATE VIEW gold.v_staleness
AS
SELECT 'bld_title' AS entity, sigungu_cd,
       COUNT(*) AS row_cnt,
       MIN(crtn_day) AS oldest_crtn_day,
       MAX(crtn_day) AS latest_crtn_day,
       DATEDIFF(DAY, MAX(valid_from), SYSDATETIME()) AS days_since_last_load
FROM silver.bld_title WHERE is_current = 1 GROUP BY sigungu_cd
UNION ALL
SELECT 'land_char', LEFT(pnu,5),
       COUNT(*), MIN(last_updt_dt), MAX(last_updt_dt),
       DATEDIFF(DAY, MAX(valid_from), SYSDATETIME())
FROM silver.land_char WHERE is_current = 1 GROUP BY LEFT(pnu,5)
UNION ALL
SELECT 'road_addr', LEFT(road_cd,5),
       COUNT(*), MIN(mvmn_de), MAX(mvmn_de),
       DATEDIFF(DAY, MAX(valid_from), SYSDATETIME())
FROM silver.road_addr WHERE is_current = 1 GROUP BY LEFT(road_cd,5);
GO

/* 연계가 끊긴 지점만 뽑는 뷰 - 파이프라인 디버깅용 */
IF OBJECT_ID('gold.v_link_gap') IS NOT NULL DROP VIEW gold.v_link_gap;
GO
CREATE VIEW gold.v_link_gap
AS
/* 대장은 있는데 토지가 없는 필지 */
SELECT 'LAND_MISSING' AS gap_type, cp.complex_cd, cp.pnu AS key_val,
       CAST(NULL AS NVARCHAR(200)) AS note
FROM gold.complex_pnu cp
LEFT JOIN silver.land_char lc ON lc.pnu = cp.pnu AND lc.is_current = 1
WHERE lc.pnu IS NULL
UNION ALL
/* 대장에 도로명 구성요소가 비어 있는 동 */
SELECT 'ROADKEY_NULL', cb.complex_cd, t.mgm_bldrgst_pk,
       N'na_road_cd=' + ISNULL(t.na_road_cd,N'<null>')
FROM gold.complex_bld cb
JOIN silver.bld_title t ON t.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND t.is_current = 1
WHERE t.na_road_cd IS NULL OR t.na_main_bun IS NULL
UNION ALL
/* PNU 조립 실패 */
SELECT 'PNU_NULL', cb.complex_cd, t.mgm_bldrgst_pk,
       N'sgg=' + ISNULL(t.sigungu_cd,N'?') + N' bjd=' + ISNULL(t.bjdong_cd,N'?')
            + N' bun=' + ISNULL(t.bun,N'?') + N' ji=' + ISNULL(t.ji,N'?')
FROM gold.complex_bld cb
JOIN silver.bld_title t ON t.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND t.is_current = 1
WHERE t.pnu IS NULL;
GO

PRINT '03_gold done.';
GO
