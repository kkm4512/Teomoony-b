/* 275. 행정동 경계 — silver.adm_boundary (2026-10-21, 사장님 요청 15:36 · SGIS 키 15:47)
   ★ 출처: 통계청 SGIS OpenAPI3 boundary/hadmarea.geojson (공식 API · 스크래핑 아님)
     year=2025 · 서울 25구 426동 + 안양 만안·동안 31동 = 457동.
     원본 좌표는 UTM-K(EPSG:5179) → 받는 쪽(VM, pyproj)에서 EPSG:4326 으로 바꿔
     etl/data/adm_boundary_sgis_2025.geojson 에 둔다. 좌표 범위가 필지(cadastral_parcel)와 같은 것을 확인했다.
   ★★ 코드가 두 체계다 — 섞지 않는다.
     adm_cd_sgis : SGIS(통계청) 코드. 성북구 = 11080  ← 경계가 들고 온 코드 그대로
     adm_cd_mois : 행정안전부 행정동 코드. 성북구 = 11290 ← 상가(semas_store.adong_cd)가 쓰는 코드
     둘을 **이름으로 잇지 않는다**(정책 1장). 276 이 **상가 점의 위치**로 잇고, 근거(몇 개 중 몇 개)를 남긴다.
   ★ 파생 표다 — 적재기가 해마다 그 해 것을 지우고 다시 넣는다(year 단위).
   ★ 다시 돌려도 된다. */
SET NOCOUNT ON;
GO
IF OBJECT_ID('silver.adm_boundary') IS NULL
CREATE TABLE silver.adm_boundary (
    adm_cd_sgis   VARCHAR(10)    NOT NULL,
    year          CHAR(4)        NOT NULL,
    adm_nm        NVARCHAR(80)   NOT NULL,   -- '서울특별시 성북구 돈암1동' (SGIS 원문)
    emd_nm        NVARCHAR(40)   NULL,       -- 끝 토막 '돈암1동' (화면 이름표용, 잇는 데 안 쓴다)
    sgg_cd_sgis   VARCHAR(5)     NULL,
    geom          geometry       NULL,
    geojson       NVARCHAR(MAX)  NULL,
    bbox_minx DECIMAL(12,7) NULL, bbox_miny DECIMAL(12,7) NULL,
    bbox_maxx DECIMAL(12,7) NULL, bbox_maxy DECIMAL(12,7) NULL,
    centroid_lat DECIMAL(11,8) NULL, centroid_lng DECIMAL(12,8) NULL,
    adm_cd_mois   VARCHAR(10)    NULL,       -- 276 이 채운다. 모르면 NULL
    mois_nm       NVARCHAR(60)   NULL,       -- 그 코드의 상가 쪽 이름(확인용)
    연결근거      NVARCHAR(40)   NULL,
    연결상가      INT            NULL,       -- 이 경계 안 상가 중 그 코드를 가진 수
    상가수        INT            NULL,       -- 이 경계 안 상가 전체
    연결비율      DECIMAL(5,2)   NULL,       -- 연결상가 / 상가수 x 100
    src           NVARCHAR(80)   NULL,
    load_dtm      DATETIME2(0)   NOT NULL CONSTRAINT df_adm_boundary_dtm DEFAULT SYSDATETIME(),
    CONSTRAINT pk_adm_boundary PRIMARY KEY CLUSTERED (adm_cd_sgis, year)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.spatial_indexes WHERE name = 'sx_adm_boundary_geom')
    CREATE SPATIAL INDEX sx_adm_boundary_geom ON silver.adm_boundary (geom)
        USING GEOMETRY_AUTO_GRID WITH (BOUNDING_BOX = (124, 33, 132, 39));
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_adm_boundary_mois')
    CREATE INDEX ix_adm_boundary_mois ON silver.adm_boundary (adm_cd_mois) WHERE adm_cd_mois IS NOT NULL;
GO
PRINT '275 완료 - silver.adm_boundary';
