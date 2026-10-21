/* 154. 용도지역 (VWorld LT_C_UQ111) — 테이블과 뷰 (2026-10-18)

   ★ 원본에 자연키가 없다
     속성이 uname/dyear/dnum/sido_name/sigg_name 다섯뿐이고, 한 결정번호가
     여러 폴리곤을 덮는다. 그래서 **속성+좌표의 sha256 을 키로 쓴다.**
     지오메트리가 곧 정체성이다 — 모양이 바뀌면 다른 구역으로 본다.

   ★ 시군구 코드를 만들지 않는다
     sigg_name 은 원본 그대로 **표시용**으로만 둔다. 이름으로 코드를 지어
     붙이면 정책 1장이 금지한 '조용히 틀린 코드' 가 된다.
     단지와의 연결은 **전부 공간교차**다 (11-26 과 같은 방법).

   ★ 범위 안 전량 교체
     적재기가 한 구를 다시 받으면, 이번에 못 본 키는 is_current=0 으로 닫는다.
     안 그러면 다시 그려진 구역의 옛 폴리곤이 영원히 살아 있는다.
*/
IF SCHEMA_ID('silver') IS NULL EXEC('CREATE SCHEMA silver');
GO
IF OBJECT_ID('silver.land_use_zone') IS NULL
CREATE TABLE silver.land_use_zone (
    zone_sk        BIGINT IDENTITY(1,1) NOT NULL,
    zone_key       CHAR(64)       NOT NULL,   -- sha256(속성+좌표)
    uname          NVARCHAR(100)  NULL,       -- 제2종일반주거지역 ...
    dyear          CHAR(4)        NULL,       -- 결정연도
    dnum           VARCHAR(20)    NULL,       -- 결정번호
    sido_name      NVARCHAR(40)   NULL,
    sigg_name      NVARCHAR(40)   NULL,       -- 표시용. 조인에 쓰지 않는다
    geojson        NVARCHAR(MAX)  NULL,
    geom           geometry       NULL,       -- SRID 4326
    centroid_lat   DECIMAL(10,7)  NULL,
    centroid_lng   DECIMAL(10,7)  NULL,
    bbox_minx      DECIMAL(12,7)  NULL,
    bbox_miny      DECIMAL(12,7)  NULL,
    bbox_maxx      DECIMAL(12,7)  NULL,
    bbox_maxy      DECIMAL(12,7)  NULL,
    area_m2_approx DECIMAL(18,2)  NULL,
    src            VARCHAR(40)    NOT NULL DEFAULT 'VWORLD_LT_C_UQ111',
    row_hash       BINARY(32)     NOT NULL,
    src_run_id     BIGINT         NULL,
    valid_from     DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    valid_to       DATETIME2(0)   NOT NULL DEFAULT '9999-12-31',
    is_current     BIT            NOT NULL DEFAULT 1,
    CONSTRAINT pk_land_use_zone PRIMARY KEY CLUSTERED (zone_sk)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='uq_luz_current')
CREATE UNIQUE INDEX uq_luz_current ON silver.land_use_zone (zone_key) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_luz_bbox')
CREATE INDEX ix_luz_bbox ON silver.land_use_zone (bbox_minx, bbox_maxx, bbox_miny, bbox_maxy)
    INCLUDE (uname) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_luz_sigg')
CREATE INDEX ix_luz_sigg ON silver.land_use_zone (sigg_name) WHERE is_current = 1;
GO

/* 단지 x 용도지역 — 필지 폴리곤과의 공간교차.
   한 단지가 두 용도지역에 걸치는 일이 흔하므로 **행을 여러 개 낸다.**
   교차면적은 도(degree) 제곱이라 절대값에 뜻이 없다. 비중 계산에만 쓴다.
   ★ 비중을 뷰 안에서 미리 내지 않는다 — 단지 하나를 볼 때만 묶으면 되고,
     전체에 대해 미리 묶으면 쓰지도 않을 계산을 매번 한다. */
IF OBJECT_ID('gold.v_complex_zone') IS NOT NULL DROP VIEW gold.v_complex_zone;
GO
CREATE VIEW gold.v_complex_zone
AS
SELECT cp.complex_id,
       z.zone_key, z.uname, z.dyear, z.dnum,
       xarea = p.geom.STIntersection(z.geom).STArea()
  FROM gold.complex_pnu cp
  JOIN silver.cadastral_parcel p
    ON p.pnu = cp.pnu AND p.is_current = 1 AND p.geom IS NOT NULL
  JOIN silver.land_use_zone z
    ON z.is_current = 1 AND z.geom IS NOT NULL
   AND z.bbox_minx <= p.bbox_maxx AND z.bbox_maxx >= p.bbox_minx
   AND z.bbox_miny <= p.bbox_maxy AND z.bbox_maxy >= p.bbox_miny
   AND z.geom.STIntersects(p.geom) = 1;
GO
PRINT '154 완료 — silver.land_use_zone / gold.v_complex_zone';
