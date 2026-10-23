/* 2026-10-24 01:12 사장님 "학교를 기준으로 어떤 학군에 속해 어떤 학교로 갈 수 있는지" — 학구도 7종 중 나머지 셋(한국교육시설안전원 · 이용 제한 없음 · 기준일 2026-09-20)
   ① silver.school_group      중학교 학교군(M) · 고등학교 학교군(H) 경계 — 초등 통학구역(silver.school_zone)과 같은 꼴
   ② silver.school_zone_link  학교학구도연계정보 CSV: 학구ID(Z… — 초등 통학구역 · 중학교군 · 고교 학군) ↔ 학교ID(B… — silver.school 과 **같은 코드**)
   ★ 이름으로 잇지 않는다. 연계표가 공식 대응표다. */
IF OBJECT_ID('silver.school_group') IS NULL
CREATE TABLE silver.school_group (
    group_sk     BIGINT IDENTITY(1,1) PRIMARY KEY,
    kind         CHAR(1)        NOT NULL,          -- M 중학교 학교군 · H 고등학교 학교군
    hakgudo_id   VARCHAR(20)    NOT NULL,
    hakgudo_nm   NVARCHAR(200)  NULL,
    hakgudo_gb   VARCHAR(4)     NULL,              -- 원문 HAKGUDO_GB (0 단독 · 1 공동)
    sd_cd        VARCHAR(4)     NULL,
    sgg_cd       VARCHAR(8)     NULL,
    edu_nm       NVARCHAR(100)  NULL,
    base_dt      VARCHAR(12)    NULL,
    geom         GEOMETRY       NOT NULL,
    bbox_minx    FLOAT NULL, bbox_miny FLOAT NULL, bbox_maxx FLOAT NULL, bbox_maxy FLOAT NULL,
    collected_at CHAR(8)        NOT NULL
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ux_school_group_id')
    CREATE UNIQUE INDEX ux_school_group_id ON silver.school_group (kind, hakgudo_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'sx_school_group_geom')
    CREATE SPATIAL INDEX sx_school_group_geom ON silver.school_group (geom)
      USING GEOMETRY_AUTO_GRID WITH (BOUNDING_BOX = (124, 33, 132, 39));
GO
IF OBJECT_ID('silver.school_zone_link') IS NULL
CREATE TABLE silver.school_zone_link (
    hakgudo_id   VARCHAR(20)    NOT NULL,
    school_id    VARCHAR(20)    NOT NULL,
    school_nm    NVARCHAR(100)  NULL,              -- 원문(검산용)
    school_lvl   NVARCHAR(10)   NULL,              -- 초등학교 · 중학교 · 고등학교
    sido_edu_cd  VARCHAR(10)    NULL,
    edu_cd       VARCHAR(10)    NULL,
    edu_nm       NVARCHAR(100)  NULL,
    base_dt      VARCHAR(12)    NULL,
    collected_at CHAR(8)        NOT NULL,
    CONSTRAINT pk_school_zone_link PRIMARY KEY (hakgudo_id, school_id)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_school_zone_link_s')
    CREATE INDEX ix_school_zone_link_s ON silver.school_zone_link (school_id);
GO
SELECT j = (SELECT 군 = (SELECT COUNT(*) FROM silver.school_group), 연계 = (SELECT COUNT(*) FROM silver.school_zone_link) FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
