/* 161. 정비사업 구역 (서울플랜+ UQ120) — 테이블과 뷰 (2026-10-19)

   출처: 서울 열린데이터광장 OA-22712「서울시 도시계획사업 현황(서울플랜+) 공간정보」
   라이선스: 공공누리 제4유형 (출처표시 + 상업적 이용금지 + 변경금지)
     ★ **비상업적 이용**이라는 전제로 적재한다. 화면에 출처를 표시한다.
       상업화하면 도시계획상임기획과(02-2133-8339)에 별도 허락이 필요하다.

   ★ 원본은 EPSG:5174 다. 적재 전에 **pyproj 로 4326 으로 변환**해 두었다
     (etl/data/uq120_4326.ndjson). 손으로 TM 역산하지 않았다 — 틀려도
     그럴듯한 값이 나와서 조용히 틀리기 때문이다.

   ★ 자연키가 있다: PRESENT_SN (예 11530UQ120PS202608050002).
     용도지역(11-40)과 달리 좌표 해시를 쓸 필요가 없다.

   ★ 단지와는 **공간교차**로 잇는다. 구역에는 PNU 가 없다.
*/
IF OBJECT_ID('silver.redev_zone') IS NULL
CREATE TABLE silver.redev_zone (
    redev_sk       BIGINT IDENTITY(1,1) NOT NULL,
    present_sn     VARCHAR(40)    NOT NULL,   -- 자연키
    zone_nm        NVARCHAR(300)  NULL,       -- DGM_NM 구역명
    lclas_cl       VARCHAR(10)    NULL,       -- 대분류 코드 (BZ100 정비사업 ...)
    sclas_cl       VARCHAR(10)    NULL,       -- 소분류 코드 (BZ103 재개발(주택정비형) ...)
    atrb_se        VARCHAR(10)    NULL,
    biz_lclas_nm   NVARCHAR(60)   NULL,       -- 코드표로 푼 한글
    biz_mlsfc_nm   NVARCHAR(60)   NULL,
    biz_nm         NVARCHAR(60)   NULL,
    propel_cd      VARCHAR(10)    NULL,       -- 추진단계 코드
    propel_nm      NVARCHAR(60)   NULL,       -- 추진단계 한글 (구역지정/조합설립인가/착공/준공 ...)
    signgu_se      CHAR(5)        NULL,       -- 시군구코드 — ★ 원본이 **코드로** 준다
    area_m2        DECIMAL(18,2)  NULL,       -- DGM_AR (원본 제공 면적)
    create_dat     CHAR(8)        NULL,
    geojson        NVARCHAR(MAX)  NULL,
    geom           geometry       NULL,       -- SRID 4326
    centroid_lat   DECIMAL(10,7)  NULL,
    centroid_lng   DECIMAL(10,7)  NULL,
    bbox_minx      DECIMAL(12,7)  NULL,
    bbox_miny      DECIMAL(12,7)  NULL,
    bbox_maxx      DECIMAL(12,7)  NULL,
    bbox_maxy      DECIMAL(12,7)  NULL,
    src            VARCHAR(40)    NOT NULL DEFAULT 'SEOUL_OA22712_UQ120',
    row_hash       BINARY(32)     NOT NULL,
    src_run_id     BIGINT         NULL,
    valid_from     DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    valid_to       DATETIME2(0)   NOT NULL DEFAULT '9999-12-31',
    is_current     BIT            NOT NULL DEFAULT 1,
    CONSTRAINT pk_redev_zone PRIMARY KEY CLUSTERED (redev_sk)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='uq_redev_current')
CREATE UNIQUE INDEX uq_redev_current ON silver.redev_zone (present_sn) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_redev_bbox')
CREATE INDEX ix_redev_bbox ON silver.redev_zone (bbox_minx, bbox_maxx, bbox_miny, bbox_maxy)
    INCLUDE (zone_nm, biz_nm, propel_nm) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_redev_sgg')
CREATE INDEX ix_redev_sgg ON silver.redev_zone (signgu_se) WHERE is_current = 1;
GO

/* 단지 x 정비구역.
   ★ v_complex_zone(용도지역)과 같은 함정이 있다 — 뷰 안에 STIntersection 이
     있으므로 **반드시 complex_id 로 걸러서** 쓴다. 안 거르면 81,143 단지를
     전부 교차시킨다(11-41 에서 10분 넘게 걸렸다). */
IF OBJECT_ID('gold.v_complex_redev') IS NOT NULL DROP VIEW gold.v_complex_redev;
GO
CREATE VIEW gold.v_complex_redev
AS
SELECT cp.complex_id,
       r.present_sn, r.zone_nm, r.biz_lclas_nm, r.biz_nm,
       r.propel_cd, r.propel_nm, r.area_m2,
       xarea = p.geom.STIntersection(r.geom).STArea(),
       parea = p.geom.STArea()
  FROM gold.complex_pnu cp
  JOIN silver.cadastral_parcel p
    ON p.pnu = cp.pnu AND p.is_current = 1 AND p.geom IS NOT NULL
  JOIN silver.redev_zone r
    ON r.is_current = 1 AND r.geom IS NOT NULL
   AND r.bbox_minx <= p.bbox_maxx AND r.bbox_maxx >= p.bbox_minx
   AND r.bbox_miny <= p.bbox_maxy AND r.bbox_maxy >= p.bbox_miny
   AND r.geom.STIntersects(p.geom) = 1;
GO
PRINT '161 완료 — silver.redev_zone / gold.v_complex_redev';
