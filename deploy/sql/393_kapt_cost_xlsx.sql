/* 393 K-apt 자료실 '관리비공개의무단지 관리비정보' 연도별 엑셀 → silver.kapt_cost_xlsx (2026-10-31 사장님 "관리비도 엑셀로 수집할 수 있는 게 있지 않아?" · "ㄱㄱ")
   ★ 원천: K-apt(공동주택관리정보시스템 · 국토교통부 · 한국부동산원) 소통마당 › 자료실 › 관리비정보 — 2018 ~ 올해 연도별 파일, 주 1회 다시 올림.
     공공데이터포털 '국토교통부_공동주택 단지 관리비 정보'(3039714)도 이 글로 이어진다.
   ★ 칸 = 엑셀 머리 그대로(52칸 · 2025년 파일 기준). 값은 글자를 숫자로만 바꾼다('2.9551852E7' → 29551852) — 계산하거나 고치지 않는다.
   ★ API 표(silver.kapt_cost · 31 오퍼레이션 · 세부 항목)와 **섞지 않는다**. K-apt 는 엑셀을 '단순 참고자료 · 정확한 것은 OpenAPI' 라고 안내한다 →
     화면은 API 를 먼저 쓰고, API 로 안 받은 달만 이 표로 채운다(gold.v_kapt_cost_month).
   ★ 같은 (단지코드, 발생년월)이 새 파일에서 바뀌면 덮고 바뀐수 +1(처음때는 남긴다). 지우지 않는다. */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
IF OBJECT_ID('silver.kapt_cost_xlsx') IS NULL
CREATE TABLE silver.kapt_cost_xlsx (
    kapt_code   VARCHAR(20)   NOT NULL,
    ym          CHAR(6)       NOT NULL,
    [시도] NVARCHAR(40) NULL, [시군구] NVARCHAR(40) NULL, [읍면] NVARCHAR(40) NULL, [동리] NVARCHAR(40) NULL, [단지명] NVARCHAR(200) NULL,
    [공용관리비(합계)] DECIMAL(20,4) NULL,
    [일반관리비(합계)] DECIMAL(20,4) NULL,
    [인건비] DECIMAL(20,4) NULL,
    [제사무비] DECIMAL(20,4) NULL,
    [제세공과금] DECIMAL(20,4) NULL,
    [피복비] DECIMAL(20,4) NULL,
    [교육훈련비] DECIMAL(20,4) NULL,
    [차량유지비] DECIMAL(20,4) NULL,
    [그밖의부대비용] DECIMAL(20,4) NULL,
    [청소비] DECIMAL(20,4) NULL,
    [경비비] DECIMAL(20,4) NULL,
    [소독비] DECIMAL(20,4) NULL,
    [승강기유지비] DECIMAL(20,4) NULL,
    [지능형네트워크유지비] DECIMAL(20,4) NULL,
    [수선유지비(합계)] DECIMAL(20,4) NULL,
    [수선비] DECIMAL(20,4) NULL,
    [시설유지비] DECIMAL(20,4) NULL,
    [안전점검비] DECIMAL(20,4) NULL,
    [재해예방비] DECIMAL(20,4) NULL,
    [위탁관리수수료] DECIMAL(20,4) NULL,
    [개별사용료계] DECIMAL(20,4) NULL,
    [난방비(공용)] DECIMAL(20,4) NULL,
    [난방비(전용)] DECIMAL(20,4) NULL,
    [급탕비(공용)] DECIMAL(20,4) NULL,
    [급탕비(전용)] DECIMAL(20,4) NULL,
    [가스사용료(공용)] DECIMAL(20,4) NULL,
    [가스사용료(전용)] DECIMAL(20,4) NULL,
    [전기료(공용)] DECIMAL(20,4) NULL,
    [전기료(전용)] DECIMAL(20,4) NULL,
    [수도료(공용)] DECIMAL(20,4) NULL,
    [수도료(전용)] DECIMAL(20,4) NULL,
    [TV수신료] DECIMAL(20,4) NULL,
    [정화조오물수수료] DECIMAL(20,4) NULL,
    [생활폐기물수수료] DECIMAL(20,4) NULL,
    [입대의운영비] DECIMAL(20,4) NULL,
    [건물보험료] DECIMAL(20,4) NULL,
    [선관위운영비] DECIMAL(20,4) NULL,
    [기타] DECIMAL(20,4) NULL,
    [장충금 월부과액] DECIMAL(20,4) NULL,
    [장충금 월사용액] DECIMAL(20,4) NULL,
    [장충금 총적립금액] DECIMAL(20,4) NULL,
    [장충금 적립률] DECIMAL(20,4) NULL,
    [잡수입 월수입금액] DECIMAL(20,4) NULL,
    [입주자기여수익] DECIMAL(20,4) NULL,
    [공동기여수익] DECIMAL(20,4) NULL,
    파일        NVARCHAR(200) NOT NULL,
    행해시      VARBINARY(32) NOT NULL,
    처음때      DATETIME2(0)  NOT NULL CONSTRAINT df_kcx_t0 DEFAULT SYSDATETIME(),
    바뀐때      DATETIME2(0)  NOT NULL CONSTRAINT df_kcx_t1 DEFAULT SYSDATETIME(),
    바뀐수      INT           NOT NULL CONSTRAINT df_kcx_n DEFAULT 0,
    CONSTRAINT pk_kapt_cost_xlsx PRIMARY KEY (kapt_code, ym)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_kcx_ym' AND object_id = OBJECT_ID('silver.kapt_cost_xlsx'))
    CREATE INDEX ix_kcx_ym ON silver.kapt_cost_xlsx (ym) INCLUDE (kapt_code, [공용관리비(합계)], [개별사용료계], [장충금 월부과액]);
GO
/* 받은 파일 기록(이름 · 줄 수 · 새로 · 바뀜) */
IF OBJECT_ID('ops.kapt_cost_xlsx_file') IS NULL
CREATE TABLE ops.kapt_cost_xlsx_file (파일 NVARCHAR(200) NOT NULL PRIMARY KEY, 글번호 VARCHAR(20) NULL, 줄 INT NULL, 새로 INT NULL, 바뀜 INT NULL, 같음 INT NULL, 넣은때 DATETIME2(0) NOT NULL DEFAULT SYSDATETIME());
GO
SELECT 표 = OBJECT_ID('silver.kapt_cost_xlsx'), 칸 = (SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID('silver.kapt_cost_xlsx'));
