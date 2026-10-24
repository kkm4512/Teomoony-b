/* 349 GIS건물통합정보(VWorld NED getBldgisSpceWFS) — 위반건축물 (2026-10-24 18:00 사장님 "위반건축물 데이터도 주나? 웹사이트에 표시하면 좋긴해")
   ★ 국토부 '위반건축물 API' 는 따로 없다(공공데이터 분쟁조정 사례: 제공 거부). 건축HUB 대용량 53종에도 위반 칸이 없다.
     그런데 GIS건물통합정보(세움터 대장 속성 + 건물 도형, 국가공간정보센터)에 **violt_bild(Y/N)** 가 있다 — 대장 위에 찍히는 '위반건축물' 표시.
   ★ 원문 그대로: 속성 전부를 attrs_json 에 둔다(도형은 안 받는다). 값이 바뀌면 SCD2 새 버전 — 위반 지정 · 해제가 이력으로 남는다.
   ★ 대장 잇기(gold.bld_violation)는 **pnu 같음 + 대장PK 끝자리 = buld_idntfc_no 가 하나뿐** 일 때만.
     GIS 는 옛 건물 도형이 남아 있기도 하다(재건축 뒤 1982 대장 값 그대로) — 이름 · 면적으로 맞추지 않는다. */
IF OBJECT_ID('silver.bld_gis') IS NULL
CREATE TABLE silver.bld_gis (
    bld_gis_sk        BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT pk_bld_gis PRIMARY KEY,
    gis_idntfc_no     VARCHAR(40)   NOT NULL,
    pnu               CHAR(19)      NULL,
    sgg_cd            CHAR(5)       NULL,
    buld_idntfc_no    VARCHAR(30)   NULL,
    refrn_systm_cntc_no VARCHAR(40) NULL,
    regstr_se_code    VARCHAR(4)    NULL,
    buld_prpos_code   VARCHAR(10)   NULL,
    buld_nm           NVARCHAR(200) NULL,
    dong_nm           NVARCHAR(200) NULL,
    use_confm_de      VARCHAR(10)   NULL,
    totar             DECIMAL(19,2) NULL,
    ground_floor_co   INT           NULL,
    undgrnd_floor_co  INT           NULL,
    violt_bild        CHAR(1)       NULL,
    data_creat_change_de VARCHAR(10) NULL,
    last_updt_dt      VARCHAR(20)   NULL,
    attrs_json        NVARCHAR(MAX) NULL,
    row_hash          BINARY(32)    NOT NULL,
    valid_from        DATETIME2(0)  NOT NULL CONSTRAINT df_bld_gis_vf DEFAULT SYSDATETIME(),
    valid_to          DATETIME2(0)  NULL,
    is_current        BIT           NOT NULL CONSTRAINT df_bld_gis_cur DEFAULT 1,
    마지막본시각       DATETIME2(0)  NOT NULL CONSTRAINT df_bld_gis_seen DEFAULT SYSDATETIME()
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ux_bld_gis_cur' AND object_id = OBJECT_ID('silver.bld_gis'))
    CREATE UNIQUE INDEX ux_bld_gis_cur ON silver.bld_gis (gis_idntfc_no) INCLUDE (row_hash) WHERE is_current = 1;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_bld_gis_pnu' AND object_id = OBJECT_ID('silver.bld_gis'))
    CREATE INDEX ix_bld_gis_pnu ON silver.bld_gis (pnu, is_current) INCLUDE (buld_idntfc_no, violt_bild, data_creat_change_de);
IF OBJECT_ID('silver.bld_gis_done') IS NULL
CREATE TABLE silver.bld_gis_done (
    sgg_cd   CHAR(5)  NOT NULL CONSTRAINT pk_bld_gis_done PRIMARY KEY,
    조각     INT NOT NULL, 수신 INT NOT NULL, 건물 INT NOT NULL, 실패조각 INT NOT NULL,
    받은시각 DATETIME2(0) NOT NULL CONSTRAINT df_bld_gis_done DEFAULT SYSDATETIME()
);
GO
/* 대장 잇기 — 파생(언제든 다시 만든다) */
CREATE OR ALTER PROCEDURE gold.usp_refresh_bld_violation @sgg CHAR(5) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF OBJECT_ID('gold.bld_violation') IS NULL
        CREATE TABLE gold.bld_violation (
            mgm_bldrgst_pk VARCHAR(33) NOT NULL CONSTRAINT pk_bld_violation PRIMARY KEY,
            gis_idntfc_no  VARCHAR(40) NOT NULL,
            pnu            CHAR(19)    NOT NULL,
            violt_bild     CHAR(1)     NOT NULL,
            기준일          VARCHAR(10) NULL,
            만든때          DATETIME2(0) NOT NULL DEFAULT SYSDATETIME());
    DELETE FROM gold.bld_violation WHERE @sgg IS NULL OR pnu LIKE @sgg + '%';
    ;WITH c AS (
        SELECT g.gis_idntfc_no, g.pnu, g.violt_bild, g.data_creat_change_de, t.mgm_bldrgst_pk,
               n = COUNT(*) OVER (PARTITION BY g.gis_idntfc_no),           -- GIS 한 건물에 대장 후보가 하나뿐
               m = COUNT(*) OVER (PARTITION BY t.mgm_bldrgst_pk)            -- 대장 하나에 GIS 건물이 하나뿐
          FROM silver.bld_gis g
          JOIN silver.bld_title t ON t.is_current = 1 AND t.pnu = g.pnu
               AND RIGHT(t.mgm_bldrgst_pk, LEN(g.buld_idntfc_no)) = g.buld_idntfc_no
               /* 확인 한 겹 더: 사용승인일 또는 연면적이 대장과 같아야(강남 18,814 줄 실측 — 다 맞았다. 어긋나면 잇지 않는다) */
               AND (REPLACE(g.use_confm_de, '-', '') = t.use_apr_day OR ABS(g.totar - t.tot_area) < 1)
         WHERE g.is_current = 1 AND g.violt_bild IN ('Y', 'N') AND g.buld_idntfc_no IS NOT NULL AND LEN(g.buld_idntfc_no) >= 3
           AND (@sgg IS NULL OR g.pnu LIKE @sgg + '%'))
    INSERT gold.bld_violation (mgm_bldrgst_pk, gis_idntfc_no, pnu, violt_bild, 기준일)
    SELECT mgm_bldrgst_pk, gis_idntfc_no, pnu, violt_bild, data_creat_change_de FROM c WHERE n = 1 AND m = 1;
    SELECT 이음 = @@ROWCOUNT;
END
GO
