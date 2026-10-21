/* ============================================================
   295_hira : 심평원 병원정보서비스 · 약국정보서비스 — 요양기관 목록(좌표 · 종별 · 의사 수) (2026-10-21, 사장님 활용신청 "완료")
   ★ 출처: apis.data.go.kr/B551182/hospInfoServicev2/getHospBasisList · pharmacyInfoService/getParmacyBasisList
     키 = DATA_GO_KR_KEY. 적재 etl/load_hira.py (서울 전체 + 경기 중 안양).
   ★ 상가정보(semas)와 **다른 축**이다: 상가정보는 사업자등록, 이건 건강보험 요양기관 신고. 종별(상급종합/종합병원/병원/의원/
     치과/한의원/요양병원)과 의사 수가 있다. 둘을 합치지 않는다 — 이름으로 잇지 않는다(정책 1장).
   ★ 진료과목 조건(dgsbjtCd)은 **신고한 진료과목 전부**라 넓다 — 구로구 의원 중 '소아청소년과 진료' 133곳, 이름에 소아가 든 곳 17곳(실측).
     그래서 과목은 여기 싣지 않는다. 간판 과목(표시과목)은 '요양기관 개설 현황' CSV(data.go.kr 15051057)에 있다.
   ★ ykiho 는 심평원이 암호화한 기호다(복호화 불가). 사라진 기관은 지우지 않고 is_current = 0.
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
IF OBJECT_ID('silver.hira_inst') IS NULL
CREATE TABLE silver.hira_inst (
    ykiho        VARCHAR(120)   NOT NULL CONSTRAINT pk_hira_inst PRIMARY KEY,
    구분         VARCHAR(5)     NOT NULL,      -- HOSP | PHARM
    yadm_nm      NVARCHAR(200)  NULL,
    cl_cd        VARCHAR(4)     NULL,          -- 01 상급종합 · 11 종합병원 · 21 병원 · 28 요양병원 · 29 정신병원 · 31 의원 · 41 치과병원 · 51 치과의원 · 92 한방병원 · 93 한의원 · 81 약국 …
    cl_cd_nm     NVARCHAR(40)   NULL,
    sido_cd      VARCHAR(8)     NULL,
    sggu_cd      VARCHAR(8)     NULL,
    sggu_nm      NVARCHAR(40)   NULL,
    emdong_nm    NVARCHAR(40)   NULL,
    addr         NVARCHAR(400)  NULL,
    telno        VARCHAR(40)    NULL,
    estb_dd      CHAR(8)        NULL,          -- 개설일
    dr_tot       INT            NULL,          -- 의사 총수
    mdept_sdr    INT            NULL,          -- 의과 전문의
    dety_sdr     INT            NULL,          -- 치과 전문의
    cmdc_sdr     INT            NULL,          -- 한방 전문의
    lat          FLOAT          NULL,
    lng          FLOAT          NULL,
    geog         GEOGRAPHY      NULL,
    raw_json     NVARCHAR(MAX)  NULL,
    is_current   BIT            NOT NULL DEFAULT 1,
    처음본시각   DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    마지막본시각 DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    사라진시각   DATETIME2(0)   NULL
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'six_hira_inst_geog')
    CREATE SPATIAL INDEX six_hira_inst_geog ON silver.hira_inst (geog);
GO
