SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* ============================================================
   Teomoony - 00_init : DB + Bronze(원본 보존) 레이어
   건축물대장을 기준(master)으로 토지/등기/지번/도로명을 연계
   ============================================================ */
IF DB_ID('Teomoony') IS NULL
BEGIN
    CREATE DATABASE Teomoony;
END
GO
ALTER DATABASE Teomoony SET RECOVERY SIMPLE;
GO
USE Teomoony;
GO

IF SCHEMA_ID('bronze') IS NULL EXEC('CREATE SCHEMA bronze');
IF SCHEMA_ID('silver') IS NULL EXEC('CREATE SCHEMA silver');
IF SCHEMA_ID('gold')   IS NULL EXEC('CREATE SCHEMA gold');
IF SCHEMA_ID('meta')   IS NULL EXEC('CREATE SCHEMA meta');
GO

/* ---------- meta: API 호출 카탈로그 ---------- */
IF OBJECT_ID('meta.api_source') IS NULL
CREATE TABLE meta.api_source (
    source_id        INT IDENTITY(1,1) PRIMARY KEY,
    domain           VARCHAR(20)   NOT NULL,  -- BLDRGST | LAND | REGISTRY | JIBUN | ROADADDR
    provider         NVARCHAR(100) NOT NULL,  -- 국토교통부 / 도로명주소개발자센터 ...
    operation        VARCHAR(100)  NOT NULL,  -- getBrTitleInfo ...
    base_url         VARCHAR(500)  NOT NULL,
    resp_format      VARCHAR(10)   NOT NULL DEFAULT 'xml',
    refresh_cycle    VARCHAR(30)   NULL,      -- daily/monthly/on-demand
    note             NVARCHAR(1000) NULL,
    created_at       DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT uq_api_source UNIQUE (domain, operation)
);
GO

/* ---------- meta: 수집 실행 이력 (현행화 추적의 핵심) ---------- */
IF OBJECT_ID('meta.ingest_run') IS NULL
CREATE TABLE meta.ingest_run (
    run_id           BIGINT IDENTITY(1,1) PRIMARY KEY,
    source_id        INT           NOT NULL REFERENCES meta.api_source(source_id),
    run_mode         VARCHAR(20)   NOT NULL,  -- FULL | DELTA | SINGLE
    scope_key        NVARCHAR(200) NULL,      -- 시군구코드 등 호출 스코프
    started_at       DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    finished_at      DATETIME2(0)  NULL,
    status           VARCHAR(20)   NOT NULL DEFAULT 'RUNNING', -- RUNNING|OK|FAIL|PARTIAL
    req_count        INT           NOT NULL DEFAULT 0,
    row_count        INT           NOT NULL DEFAULT 0,
    err_msg          NVARCHAR(2000) NULL
);
GO

/* ---------- bronze: 원본 응답 그대로 보존 (스키마 변화 흡수) ----------
   공공 API는 필드가 예고 없이 늘어남 → 원본을 버리지 않는 것이 1원칙 */
IF OBJECT_ID('bronze.api_payload') IS NULL
CREATE TABLE bronze.api_payload (
    payload_id       BIGINT IDENTITY(1,1) NOT NULL,
    run_id           BIGINT        NOT NULL,
    source_id        INT           NOT NULL,
    req_url_hash     BINARY(32)    NOT NULL,          -- 중복 호출 식별
    req_params       NVARCHAR(2000) NULL,
    http_status      INT           NULL,
    result_code      VARCHAR(20)   NULL,              -- 00 / 03(NODATA) / 30(KEY) ...
    body             NVARCHAR(MAX) NULL,              -- 원본 xml/json
    body_sha256      BINARY(32)    NULL,              -- 변동 감지용
    fetched_at       DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_api_payload PRIMARY KEY CLUSTERED (payload_id)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_api_payload_dedup')
CREATE INDEX ix_api_payload_dedup ON bronze.api_payload (source_id, req_url_hash, fetched_at DESC);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_api_payload_run')
CREATE INDEX ix_api_payload_run ON bronze.api_payload (run_id);
GO

PRINT 'Teomoony init done.';
GO
