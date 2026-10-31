/* 395_mois_jscode : 행안부 행정기관(행정동)·관할구역(법정동) 코드 — 말소코드 포함 원문 (2026-10-31 사장님 "법정동·행정동 분리·통합 때 골치 아픈 상황 방지")
   원천 = 행정안전부 「행정기관(행정동) 및 관할구역(법정동) 코드 변경내역 알림」 첨부 jscodeYYYYMMDD(말소코드포함).zip
          (KIKcd_B 법정동 · KIKcd_H 행정동 · KIKmix 행정동↔관할 법정동, 각 줄에 생성일자 · 말소일자)
   적재 = etl/load_mois_jscode.py <zip>
   ★ 원문 그대로. 판(파일 날짜)마다 쌓는다 — 한 판이 그 시점까지의 전체 이력이다. 화면 · 대응표는 가장 최근 판만 본다.
   ★ 날짜는 원문 그대로 CHAR(8) 'YYYYMMDD'. 말소일자 NULL = 지금 살아 있음. */
SET NOCOUNT ON;
GO
IF OBJECT_ID('silver.mois_bdong_code') IS NULL
CREATE TABLE silver.mois_bdong_code (
    판         CHAR(8)       NOT NULL,
    법정동코드 CHAR(10)      NOT NULL,
    시도명     NVARCHAR(40)  NULL,
    시군구명   NVARCHAR(40)  NULL,
    읍면동명   NVARCHAR(40)  NULL,
    동리명     NVARCHAR(40)  NULL,
    생성일자   CHAR(8)       NULL,
    말소일자   CHAR(8)       NULL,
    받은시각   DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_mois_bdong_code PRIMARY KEY CLUSTERED (판, 법정동코드)
);
GO
IF OBJECT_ID('silver.mois_hdong_code') IS NULL
CREATE TABLE silver.mois_hdong_code (
    판         CHAR(8)       NOT NULL,
    행정동코드 CHAR(10)      NOT NULL,
    시도명     NVARCHAR(40)  NULL,
    시군구명   NVARCHAR(40)  NULL,
    읍면동명   NVARCHAR(40)  NULL,
    생성일자   CHAR(8)       NULL,
    말소일자   CHAR(8)       NULL,
    받은시각   DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_mois_hdong_code PRIMARY KEY CLUSTERED (판, 행정동코드)
);
GO
IF OBJECT_ID('silver.mois_hdong_bdong') IS NULL
CREATE TABLE silver.mois_hdong_bdong (
    판         CHAR(8)       NOT NULL,
    행정동코드 CHAR(10)      NOT NULL,
    시도명     NVARCHAR(40)  NULL,
    시군구명   NVARCHAR(40)  NULL,
    읍면동명   NVARCHAR(40)  NULL,
    법정동코드 CHAR(10)      NOT NULL,
    동리명     NVARCHAR(40)  NULL,
    생성일자   CHAR(8)       NULL,
    말소일자   CHAR(8)       NULL,
    받은시각   DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_mois_hdong_bdong PRIMARY KEY CLUSTERED (판, 행정동코드, 법정동코드)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_mois_hdong_bdong_b' AND object_id = OBJECT_ID('silver.mois_hdong_bdong'))
CREATE INDEX ix_mois_hdong_bdong_b ON silver.mois_hdong_bdong (판, 법정동코드) INCLUDE (행정동코드, 생성일자, 말소일자);
GO
IF OBJECT_ID('ops.mois_jscode_file') IS NULL
CREATE TABLE ops.mois_jscode_file (
    판       CHAR(8)       NOT NULL,
    종류     VARCHAR(4)    NOT NULL,
    줄       INT           NOT NULL,
    말소줄   INT           NOT NULL,
    파일     NVARCHAR(200) NULL,
    넣은때   DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);
GO
