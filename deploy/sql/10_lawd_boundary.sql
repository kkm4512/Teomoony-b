SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* ============================================================
   10_lawd_boundary : 법정동 경계 폴리곤

   출처 : VWorld 2D 데이터 API
          data=LT_C_ADEMD_INFO, attrFilter=emd_cd:like:<시군구코드5>
          crs=EPSG:4326

   ★ emd_cd 는 8자리다. 우리 법정동코드(10자리)는 뒤에 리코드 '00' 이 붙는다.
     lawd_cd = emd_cd + '00'  (예: 11110118 -> 1111011800 내수동)
     종로구로 확인: 87개로 meta.lawd_code 와 수가 맞는다.

   ★ 06_cadastral 과 같은 이유로 geography 가 아니라 geometry 를 쓴다.
   ============================================================ */
USE Teomoony;
GO

IF OBJECT_ID('silver.lawd_boundary') IS NULL
CREATE TABLE silver.lawd_boundary (
    boundary_sk   BIGINT IDENTITY(1,1) NOT NULL,
    lawd_cd       CHAR(10)       NOT NULL,   -- emd_cd + '00'
    emd_cd        CHAR(8)        NOT NULL,
    emd_nm        NVARCHAR(40)   NULL,
    full_nm       NVARCHAR(120)  NULL,
    sgg_cd        AS CAST(LEFT(lawd_cd,5) AS CHAR(5)) PERSISTED,
    geojson       NVARCHAR(MAX)  NULL,
    geom          geometry       NULL,       -- SRID 4326
    centroid_lat  DECIMAL(10,7)  NULL,
    centroid_lng  DECIMAL(10,7)  NULL,
    bbox_minx     DECIMAL(12,7)  NULL,
    bbox_miny     DECIMAL(12,7)  NULL,
    bbox_maxx     DECIMAL(12,7)  NULL,
    bbox_maxy     DECIMAL(12,7)  NULL,
    src           VARCHAR(30)    NOT NULL DEFAULT 'VWORLD_LT_C_ADEMD_INFO',
    row_hash      BINARY(32)     NOT NULL,
    src_run_id    BIGINT         NULL,
    valid_from    DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    valid_to      DATETIME2(0)   NOT NULL DEFAULT '9999-12-31',
    is_current    BIT            NOT NULL DEFAULT 1,
    CONSTRAINT pk_lawd_boundary PRIMARY KEY CLUSTERED (boundary_sk)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='uq_lawd_boundary_current')
CREATE UNIQUE INDEX uq_lawd_boundary_current ON silver.lawd_boundary (lawd_cd) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_lawd_boundary_centroid')
CREATE INDEX ix_lawd_boundary_centroid ON silver.lawd_boundary (centroid_lng, centroid_lat)
    INCLUDE (lawd_cd, emd_nm) WHERE is_current = 1;
GO

/* ============================================================
   법정동 단위 요약 - 지도에서 넓게 볼 때 쓰는 마커
   단지 수 / 세대 수 / 매매 최고가(해제 제외)
   ============================================================ */
IF OBJECT_ID('gold.v_lawd_map') IS NOT NULL DROP VIEW gold.v_lawd_map;
GO
CREATE VIEW gold.v_lawd_map
AS
SELECT
    b.lawd_cd, b.emd_nm, b.full_nm, b.sgg_cd,
    b.centroid_lat, b.centroid_lng,
    b.bbox_minx, b.bbox_miny, b.bbox_maxx, b.bbox_maxy,
    cx.complex_cnt, cx.dong_cnt, cx.hhld_cnt,
    t.max_amount, t.max_area, t.max_ymd, t.trade_cnt
FROM silver.lawd_boundary b
OUTER APPLY (
    SELECT COUNT(*) AS complex_cnt,
           SUM(c.dong_cnt) AS dong_cnt,
           SUM(c.hhld_cnt_sum) AS hhld_cnt
    FROM gold.complex c
    WHERE LEFT(c.rep_pnu, 10) = b.lawd_cd
) cx
OUTER APPLY (
    SELECT COUNT(*) AS trade_cnt,
           MAX(r.deal_amount) AS max_amount,
           MAX(CASE WHEN r.rn = 1 THEN r.area END)     AS max_area,
           MAX(CASE WHEN r.rn = 1 THEN r.deal_ymd END) AS max_ymd
    FROM (
        SELECT r.deal_amount, r.deal_ymd,
               CAST(FLOOR(COALESCE(r.exclu_use_ar, r.total_floor_ar)) AS INT) AS area,
               ROW_NUMBER() OVER (ORDER BY r.deal_amount DESC) AS rn
        FROM silver.rtms_trade r
        WHERE r.is_rent = 0 AND r.is_canceled = 0 AND r.deal_amount IS NOT NULL
          AND LEFT(r.match_pnu, 10) = b.lawd_cd
    ) r
) t;
GO
