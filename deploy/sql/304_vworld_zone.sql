/* 304_vworld_zone : VWorld 용도지역·지구·구역 경계 미리 받기 (2026-10-22 11:08, 사장님 "미리 받아올순없어?")
   11-186 은 누를 때마다 VWorld 를 불렀다 → 느리고 502 에 약하다. 서울·안양 범위를 레이어별로 미리 받아 둔다.
   레이어: UQ111 용도지역 · UQ141 용도구역(지구단위계획·토지거래허가·개발행위허가제한·도시자연공원구역) · UQ121 경관 · UQ123 고도
           · UQ124 방화 · UQ128 취락 · UQ129 개발진흥 · UQ162 공원·녹지 · UO101 교육환경보호 · LHZONE 공급촉진지구.
   ★ 자연키가 없다 → 레이어 + 속성 + 좌표의 sha256(zone_key) — load_landuse(154) 와 같은 규칙.
   ★ 시군구를 다 받으면 silver.vworld_zone_done 에 적는다. 화면은 받은 곳이면 DB 만, 아니면 그때 VWorld 를 부른다.
   ★ 기본은 못 본 구역을 닫지 않는다(BOX 가 옆 구를 문다 — 154 와 같은 이유). 지정이 풀린 구역은 --close-stale 로만.
   ★ silver.land_use_zone(154, 용도 겹쳐보기)은 그대로 둔다 — 이 표와 섞지 않는다.
*/
SET NOCOUNT ON;
GO
IF OBJECT_ID('silver.vworld_zone') IS NULL
CREATE TABLE silver.vworld_zone (
    zone_sk        BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT pk_vworld_zone PRIMARY KEY,
    layer          VARCHAR(20)    NOT NULL,
    zone_key       CHAR(64)       NOT NULL,
    이름           NVARCHAR(200)  NULL,       -- uname · dgm_nm · zonename (원문)
    dyear          VARCHAR(8)     NULL,
    dnum           VARCHAR(20)    NULL,
    sido_name      NVARCHAR(40)   NULL,
    sigg_name      NVARCHAR(40)   NULL,
    attrs_json     NVARCHAR(2000) NULL,       -- 속성 원문 전부
    geojson        NVARCHAR(MAX)  NULL,
    geom           geometry       NULL,       -- SRID 4326, MakeValid
    bbox_minx      DECIMAL(12,7)  NULL,
    bbox_miny      DECIMAL(12,7)  NULL,
    bbox_maxx      DECIMAL(12,7)  NULL,
    bbox_maxy      DECIMAL(12,7)  NULL,
    is_current     BIT            NOT NULL DEFAULT 1,
    처음본시각     DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    마지막본시각   DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME()
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'uq_vworld_zone_key')
    CREATE UNIQUE INDEX uq_vworld_zone_key ON silver.vworld_zone (layer, zone_key);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_vworld_zone_nm')
    CREATE INDEX ix_vworld_zone_nm ON silver.vworld_zone (layer, 이름) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'sx_vworld_zone_geom')
    CREATE SPATIAL INDEX sx_vworld_zone_geom ON silver.vworld_zone (geom)
      USING GEOMETRY_AUTO_GRID WITH (BOUNDING_BOX = (124, 33, 132, 39));
GO
IF OBJECT_ID('silver.vworld_zone_done') IS NULL
CREATE TABLE silver.vworld_zone_done (
    layer      VARCHAR(20)  NOT NULL,
    sgg_cd     CHAR(5)      NOT NULL,
    수신       INT          NOT NULL,
    빈조각     INT          NOT NULL,      -- 받다 실패한 BOX 조각 수 — 0 일 때만 '다 받음'
    받은시각   DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_vworld_zone_done PRIMARY KEY (layer, sgg_cd)
);
GO
