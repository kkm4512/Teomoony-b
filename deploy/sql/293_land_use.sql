/* ============================================================
   293_land_use : 토지이용계획(VWorld NED getLandUseAttr) — 필지마다 용도지역·지구·구역 (2026-10-21, 사장님 "ㄱㄱ")
   ★ 필지(PNU) 하나에 호출 하나. 응답 한 줄 = 그 필지에 걸린 지역·지구·구역 하나
     (prposAreaDstrcCodeNm '토지거래계약에관한허가구역' · '재개발구역' · '지구단위계획구역' · '제2종일반주거지역' …,
      cnflcAt 1 포함 / 2 저촉 / 3 접함, manageNo 가 그 지정 하나의 번호).
   ★ 사라진 지정(토지거래허가 해제 등)은 **지우지 않고** is_current = 0 · 사라진시각 — 이력이 정보다.
   ★ 받은 필지 표(land_use_done)로 '0건' 과 '안 받음' 을 가른다. 0건도 받은 것이다.
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
IF OBJECT_ID('silver.land_use_plan') IS NULL
CREATE TABLE silver.land_use_plan (
    pnu           CHAR(19)       NOT NULL,
    manage_no     VARCHAR(60)    NOT NULL,
    코드          VARCHAR(20)    NULL,        -- prposAreaDstrcCode (UQA122 · UNE200 …)
    이름          NVARCHAR(120)  NULL,        -- prposAreaDstrcCodeNm
    저촉          CHAR(1)        NULL,        -- cnflcAt 1 포함 / 2 저촉 / 3 접함
    저촉이름      NVARCHAR(10)   NULL,
    대장구분      NVARCHAR(20)   NULL,        -- regstrSeCodeNm (토지대장 / 임야대장)
    등록일        CHAR(10)       NULL,
    갱신일        CHAR(10)       NULL,        -- lastUpdtDt
    is_current    BIT            NOT NULL DEFAULT 1,
    처음본시각    DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    마지막본시각  DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    사라진시각    DATETIME2(0)   NULL,
    CONSTRAINT pk_land_use_plan PRIMARY KEY CLUSTERED (pnu, manage_no)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_land_use_nm')
    CREATE INDEX ix_land_use_nm ON silver.land_use_plan (이름) INCLUDE (pnu, 저촉) WHERE is_current = 1;
GO
IF OBJECT_ID('silver.land_use_done') IS NULL
CREATE TABLE silver.land_use_done (
    pnu        CHAR(19)      NOT NULL CONSTRAINT pk_land_use_done PRIMARY KEY,
    건수       INT           NOT NULL,
    받은시각   DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);
GO
