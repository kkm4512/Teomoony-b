SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* ============================================================
   06_cadastral : 연속지적도 (필지 폴리곤)

   출처 : VWorld 2D 데이터 API
          https://api.vworld.kr/req/data
          data=LP_PA_CBND_BUBUN, attrFilter=pnu:like:<법정동코드10>
          crs=EPSG:4326  -> 위경도로 바로 받는다 (좌표계 변환 불필요)

   ★ geography 가 아니라 geometry 를 쓴다.
     geography 는 폴리곤 링의 방향(시계/반시계)이 반대면 "지구 반대편을
     덮는 도형"이 되어 조용히 틀린 결과를 낸다. VWorld 가 어느 방향으로
     주는지 보장이 없다. geometry 는 그 규칙이 없고, 이 축척에서는
     평면 계산으로 충분하다.
   ============================================================ */
USE Teomoony;
GO

IF OBJECT_ID('silver.cadastral_parcel') IS NULL
CREATE TABLE silver.cadastral_parcel (
    parcel_sk     BIGINT IDENTITY(1,1) NOT NULL,
    pnu           CHAR(19)       NOT NULL,
    lawd_cd       AS CAST(LEFT(pnu,10) AS CHAR(10)) PERSISTED,
    jibun         NVARCHAR(40)   NULL,      -- "1대" 처럼 지번+지목약어
    bonbun        VARCHAR(10)    NULL,
    bubun         VARCHAR(10)    NULL,
    addr          NVARCHAR(300)  NULL,
    jiga          DECIMAL(19,2)  NULL,      -- 개별공시지가 (원/m2)
    gosi_year     CHAR(4)        NULL,
    gosi_month    CHAR(2)        NULL,
    /* 지오메트리 - 조회용 GeoJSON 과 연산용 geometry 를 함께 둔다.
       SQL Server 에는 ST_AsGeoJSON 이 없어서, 서빙할 때마다 WKT 를
       변환하는 대신 적재 시점에 GeoJSON 을 그대로 보관한다. */
    geojson       NVARCHAR(MAX)  NULL,      -- {"type":"MultiPolygon","coordinates":[...]}
    geom          geometry       NULL,      -- SRID 4326
    centroid_lat  DECIMAL(10,7)  NULL,
    centroid_lng  DECIMAL(10,7)  NULL,
    bbox_minx     DECIMAL(12,7)  NULL,
    bbox_miny     DECIMAL(12,7)  NULL,
    bbox_maxx     DECIMAL(12,7)  NULL,
    bbox_maxy     DECIMAL(12,7)  NULL,
    src           VARCHAR(30)    NOT NULL DEFAULT 'VWORLD_LP_PA_CBND_BUBUN',
    row_hash      BINARY(32)     NOT NULL,
    src_run_id    BIGINT         NULL,
    valid_from    DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    valid_to      DATETIME2(0)   NOT NULL DEFAULT '9999-12-31',
    is_current    BIT            NOT NULL DEFAULT 1,
    CONSTRAINT pk_cadastral_parcel PRIMARY KEY CLUSTERED (parcel_sk)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='uq_parcel_current')
CREATE UNIQUE INDEX uq_parcel_current ON silver.cadastral_parcel (pnu) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_parcel_lawd')
CREATE INDEX ix_parcel_lawd ON silver.cadastral_parcel (lawd_cd) WHERE is_current = 1;
GO
/* 지도 bbox 질의용 - 중심좌표 범위 검색 */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_parcel_centroid')
CREATE INDEX ix_parcel_centroid ON silver.cadastral_parcel (centroid_lng, centroid_lat)
    INCLUDE (pnu, jiga) WHERE is_current = 1;
GO

/* ============================================================
   단지에 지도 좌표 추가
   ============================================================ */
IF COL_LENGTH('gold.complex','centroid_lat') IS NULL
ALTER TABLE gold.complex ADD
    centroid_lat DECIMAL(10,7) NULL,
    centroid_lng DECIMAL(10,7) NULL,
    bbox_minx    DECIMAL(12,7) NULL,
    bbox_miny    DECIMAL(12,7) NULL,
    bbox_maxx    DECIMAL(12,7) NULL,
    bbox_maxy    DECIMAL(12,7) NULL,
    jiga_avg     DECIMAL(19,2) NULL,
    parcel_hit   INT           NULL;   -- 폴리곤이 붙은 필지 수
GO

/* ============================================================
   단지 좌표 재계산 - 구성 필지들의 bbox 중심
   ============================================================ */
IF OBJECT_ID('gold.usp_refresh_complex_geo') IS NOT NULL DROP PROCEDURE gold.usp_refresh_complex_geo;
GO
CREATE PROCEDURE gold.usp_refresh_complex_geo
AS
BEGIN
    SET NOCOUNT ON;
    WITH g AS (
        SELECT cp.complex_id,
               MIN(p.bbox_minx) AS minx, MIN(p.bbox_miny) AS miny,
               MAX(p.bbox_maxx) AS maxx, MAX(p.bbox_maxy) AS maxy,
               AVG(p.jiga)      AS jiga_avg,
               COUNT(p.pnu)     AS hit
        FROM gold.complex_pnu cp
        JOIN silver.cadastral_parcel p ON p.pnu = cp.pnu AND p.is_current = 1
        GROUP BY cp.complex_id
    )
    UPDATE c
       SET c.bbox_minx = g.minx, c.bbox_miny = g.miny,
           c.bbox_maxx = g.maxx, c.bbox_maxy = g.maxy,
           c.centroid_lng = CAST((g.minx + g.maxx) / 2 AS DECIMAL(10,7)),
           c.centroid_lat = CAST((g.miny + g.maxy) / 2 AS DECIMAL(10,7)),
           c.jiga_avg   = g.jiga_avg,
           c.parcel_hit = g.hit,
           c.updated_at = SYSDATETIME()
      FROM gold.complex c JOIN g ON g.complex_id = c.complex_id;
END
GO

/* ============================================================
   프론트엔드용 뷰
   ============================================================ */
IF OBJECT_ID('gold.v_complex_map') IS NOT NULL DROP VIEW gold.v_complex_map;
GO
CREATE VIEW gold.v_complex_map
AS
SELECT
    c.complex_id,
    c.complex_nm,
    c.grouping_rule,
    c.has_recap,
    c.sigungu_cd,
    c.bjdong_cd,
    l.full_nm        AS lawd_nm,
    c.rep_pnu,
    meta.fn_pnu_to_jibun(c.rep_pnu) AS rep_jibun,
    c.rep_plat_plc,
    c.rep_road_addr,
    c.dong_cnt,
    c.pnu_cnt,
    c.parcel_hit,
    c.hhld_cnt_sum,
    c.tot_area_sum,
    c.oldest_use_apr,
    c.latest_use_apr,
    c.jiga_avg,
    c.centroid_lat,
    c.centroid_lng,
    c.bbox_minx, c.bbox_miny, c.bbox_maxx, c.bbox_maxy
FROM gold.complex c
LEFT JOIN meta.lawd_code l ON l.lawd_cd = LEFT(c.rep_pnu,10);
GO

PRINT '06_cadastral done.';
GO
