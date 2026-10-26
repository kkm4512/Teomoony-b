/* 357 리 경계 (2026-10-26 사장님 "법정동까지만 보여주는데 리까지 있는 경우도 있어 추가돼야 할 것 같아")
   출처: VWorld LT_C_ADRI_INFO(법정구역 리) — 읍면동 경계(LT_C_ADEMD_INFO · silver.lawd_boundary)와 같은 공식 경로.
   ★ 읍면동 표에 섞지 않는다 — 섞으면 지도 법정동 층 · '지금 어디' 에서 읍면과 그 안의 리가 겹쳐 둘 다 걸린다. */
IF OBJECT_ID('silver.ri_boundary') IS NULL
CREATE TABLE silver.ri_boundary (
    boundary_sk   BIGINT IDENTITY(1,1) NOT NULL,
    lawd_cd       CHAR(10)       NOT NULL,   -- li_cd 10자리(읍면 8자리 + 리 2자리)
    emd_cd        AS CAST(LEFT(lawd_cd, 8) AS CHAR(8)) PERSISTED,
    sgg_cd        AS CAST(LEFT(lawd_cd, 5) AS CHAR(5)) PERSISTED,
    ri_nm         NVARCHAR(40)   NULL,
    full_nm       NVARCHAR(120)  NULL,
    geojson       NVARCHAR(MAX)  NULL,
    geom          geometry       NULL,       -- SRID 4326
    centroid_lat  DECIMAL(10,7)  NULL,
    centroid_lng  DECIMAL(10,7)  NULL,
    bbox_minx     DECIMAL(12,7)  NULL,
    bbox_miny     DECIMAL(12,7)  NULL,
    bbox_maxx     DECIMAL(12,7)  NULL,
    bbox_maxy     DECIMAL(12,7)  NULL,
    src           VARCHAR(30)    NOT NULL DEFAULT 'VWORLD_LT_C_ADRI_INFO',
    row_hash      BINARY(32)     NOT NULL,
    valid_from    DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    valid_to      DATETIME2(0)   NOT NULL DEFAULT '9999-12-31',
    is_current    BIT            NOT NULL DEFAULT 1,
    CONSTRAINT pk_ri_boundary PRIMARY KEY CLUSTERED (boundary_sk)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'uq_ri_boundary_current')
CREATE UNIQUE INDEX uq_ri_boundary_current ON silver.ri_boundary (lawd_cd) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_ri_boundary_emd')
CREATE INDEX ix_ri_boundary_emd ON silver.ri_boundary (emd_cd) INCLUDE (lawd_cd, ri_nm, bbox_minx, bbox_miny, bbox_maxx, bbox_maxy) WHERE is_current = 1;
GO
