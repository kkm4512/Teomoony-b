/* ============================================================
   298_hira_open : 심평원 '요양기관 개설 현황' — 간판 과목(표시과목) (2026-10-22, 사장님 활용신청)
   ★ 출처: api.odcloud.kr/api/15051057/v1/uddi:466a7aa3-…(2025-12-31 기준, 연 1회). 키 = DATA_GO_KR_KEY. 적재 etl/load_hira_open.py (전국 104,775).
   ★ 왜: 병원정보서비스의 진료과목은 **신고한 과목 전부**라 넓다(구로 의원 중 '소아청소년과 진료' 133 · 이름에 소아 17).
     여기 표시과목은 **간판 과목 하나**다 — '소아청소년과 의원' 을 셀 수 있다.
   ★ 잇는 키 = 암호화된요양기호(= hira_inst.ykiho). 서울 1,000 시험에서 949 일치(95%). 이름으로 잇지 않는다.
   ★ 기준일이 2025-12-31 이다 — 그 뒤 생긴 곳은 표시과목이 비고, 그 뒤 닫은 곳은 hira_inst 에 없다. 화면에 기준일을 적는다.
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
IF OBJECT_ID('silver.hira_open') IS NULL
CREATE TABLE silver.hira_open (
    ykiho        VARCHAR(120)   NOT NULL CONSTRAINT pk_hira_open PRIMARY KEY,
    기준일       CHAR(8)        NOT NULL,
    요양기관명   NVARCHAR(200)  NULL,
    요양종별     NVARCHAR(40)   NULL,
    표시과목     NVARCHAR(60)   NULL,
    개설일자     CHAR(10)       NULL,
    시도명       NVARCHAR(40)   NULL,
    시군구명     NVARCHAR(60)   NULL,
    도로명주소   NVARCHAR(400)  NULL,
    loaded_at    DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME()
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_hira_open_gwa')
    CREATE INDEX ix_hira_open_gwa ON silver.hira_open (표시과목) INCLUDE (ykiho);
GO
