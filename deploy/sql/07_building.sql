SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* ============================================================
   07_building : 건물 외곽선 (건물통합정보)

   출처 : VWorld 2D 데이터 API  data=LT_C_SPBD

   ★ 핵심 : 건물관리번호(bd_mgt_sn) 25자리의 앞 19자리가 PNU 다.

        1111018400 1 0318 0024 000002
        └ 법정동10 ┘ 산 └본번┘└부번┘└일련6┘
        └──────── 앞 19 = PNU ────────┘

     그래서 건물 -> 필지 -> 단지 연결이 주소 문자열 매칭 없이
     그냥 떨어진다. 청운동 일대 실측 97.8% 일치.

   ★ 한계 : 건축물대장의 "동"(mgm_bldrgst_pk)과 건물 폴리곤을
     1:1 로 잇는 키는 없다. PNU 레벨까지만 확실하다.
     (청운벽산빌리지 = 대장 10동 vs 폴리곤 9개)
     동 단위 매칭은 공간위치·층수 추정이 필요하고 정확도를 보장 못 한다.
   ============================================================ */
USE Teomoony;
GO

IF OBJECT_ID('silver.building_footprint') IS NULL
CREATE TABLE silver.building_footprint (
    bld_sk        BIGINT IDENTITY(1,1) NOT NULL,
    bd_mgt_sn     CHAR(25)       NOT NULL,   -- 건물관리번호
    pnu           AS CAST(LEFT(bd_mgt_sn,19) AS CHAR(19)) PERSISTED,
    lawd_cd       AS CAST(LEFT(bd_mgt_sn,10) AS CHAR(10)) PERSISTED,
    buld_nm       NVARCHAR(200)  NULL,       -- 건물명 (80% 비어 있음)
    buld_nm_dc    NVARCHAR(400)  NULL,       -- 상세건물명
    bul_eng_nm    NVARCHAR(200)  NULL,
    buld_no       NVARCHAR(40)   NULL,       -- 건물번호 "9-5"
    rd_nm         NVARCHAR(80)   NULL,       -- 도로명
    sido_nm       NVARCHAR(40)   NULL,
    sigungu_nm    NVARCHAR(40)   NULL,
    emd_nm        NVARCHAR(40)   NULL,       -- VWorld 가 'gu' 로 주지만 실제로는 법정동명
    gro_flo_co    INT            NULL,       -- 지상층수
    geojson       NVARCHAR(MAX)  NULL,
    geom          geometry       NULL,       -- SRID 4326
    centroid_lat  DECIMAL(10,7)  NULL,
    centroid_lng  DECIMAL(10,7)  NULL,
    bbox_minx     DECIMAL(12,7)  NULL,
    bbox_miny     DECIMAL(12,7)  NULL,
    bbox_maxx     DECIMAL(12,7)  NULL,
    bbox_maxy     DECIMAL(12,7)  NULL,
    /* 위경도 폴리곤의 평면 면적은 degree^2 라 의미가 없다.
       위도 보정한 근사치를 따로 둔다. 대장의 archArea 와 대조하는 용도이지
       공식 면적이 아니다. */
    area_m2_approx DECIMAL(19,2) NULL,
    src           VARCHAR(30)    NOT NULL DEFAULT 'VWORLD_LT_C_SPBD',
    row_hash      BINARY(32)     NOT NULL,
    src_run_id    BIGINT         NULL,
    valid_from    DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    valid_to      DATETIME2(0)   NOT NULL DEFAULT '9999-12-31',
    is_current    BIT            NOT NULL DEFAULT 1,
    CONSTRAINT pk_building_footprint PRIMARY KEY CLUSTERED (bld_sk)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='uq_building_current')
CREATE UNIQUE INDEX uq_building_current ON silver.building_footprint (bd_mgt_sn) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_building_pnu')
CREATE INDEX ix_building_pnu ON silver.building_footprint (pnu)
    INCLUDE (bd_mgt_sn, buld_nm, gro_flo_co) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_building_centroid')
CREATE INDEX ix_building_centroid ON silver.building_footprint (centroid_lng, centroid_lat)
    INCLUDE (bd_mgt_sn, pnu) WHERE is_current = 1;
GO

/* ---------- 단지 집계에 건물 추가 ---------- */
IF COL_LENGTH('gold.complex','bld_cnt') IS NULL
ALTER TABLE gold.complex ADD
    bld_cnt   INT NULL,     -- 건물 폴리곤 수 (대장의 동 수와 다를 수 있음)
    max_floor INT NULL;     -- 최고 지상층수
GO

IF OBJECT_ID('gold.usp_refresh_complex_building') IS NOT NULL
    DROP PROCEDURE gold.usp_refresh_complex_building;
GO
CREATE PROCEDURE gold.usp_refresh_complex_building
AS
BEGIN
    SET NOCOUNT ON;
    WITH b AS (
        SELECT cp.complex_id,
               COUNT(DISTINCT f.bd_mgt_sn) AS bld_cnt,
               MAX(f.gro_flo_co)           AS max_floor
        FROM gold.complex_pnu cp
        JOIN silver.building_footprint f ON f.pnu = cp.pnu AND f.is_current = 1
        GROUP BY cp.complex_id
    )
    UPDATE c
       SET c.bld_cnt = b.bld_cnt, c.max_floor = b.max_floor, c.updated_at = SYSDATETIME()
      FROM gold.complex c JOIN b ON b.complex_id = c.complex_id;

    /* 건물이 하나도 안 붙은 단지는 0 으로 (NULL = 미계산과 구분) */
    UPDATE c SET c.bld_cnt = 0
      FROM gold.complex c
     WHERE c.bld_cnt IS NULL
       AND EXISTS (SELECT 1 FROM gold.complex_pnu cp WHERE cp.complex_id = c.complex_id);
END
GO

/* ---------- 프론트엔드 뷰 갱신 ---------- */
IF OBJECT_ID('gold.v_complex_map') IS NOT NULL DROP VIEW gold.v_complex_map;
GO
CREATE VIEW gold.v_complex_map
AS
SELECT
    c.complex_id, c.complex_nm, c.grouping_rule, c.has_recap,
    c.sigungu_cd, c.bjdong_cd, l.full_nm AS lawd_nm,
    c.rep_pnu, meta.fn_pnu_to_jibun(c.rep_pnu) AS rep_jibun,
    c.rep_plat_plc, c.rep_road_addr,
    c.dong_cnt,          -- 건축물대장 기준 동 수
    c.bld_cnt,           -- 건물 폴리곤 수 (대장 동 수와 다를 수 있음)
    c.max_floor,
    c.pnu_cnt, c.parcel_hit,
    c.hhld_cnt_sum, c.tot_area_sum,
    c.oldest_use_apr, c.latest_use_apr,
    c.jiga_avg,
    c.centroid_lat, c.centroid_lng,
    c.bbox_minx, c.bbox_miny, c.bbox_maxx, c.bbox_maxy
FROM gold.complex c
LEFT JOIN meta.lawd_code l ON l.lawd_cd = LEFT(c.rep_pnu,10);
GO

PRINT '07_building done.';
GO
