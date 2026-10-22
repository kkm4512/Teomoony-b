/* 310_inquiry : 오류 카드의 '문의 남기기' (2026-10-22 사장님 "다시하기 빼고 문의남기기 · 로그인된 유저만")
   ★ 로그인한 사용자만 남긴다(서버가 토큰을 확인 — 화면 버튼만 숨기는 게 아니다).
   ★ 담는 것: 누가(user_id·아이디) · 언제 · 무엇이 실패 · 오류번호 · 단지코드 · 화면 주소 · 사용자가 쓴 글.
     IP·브라우저 정보는 담지 않는다(이용현황과 같은 원칙 — 담으면 지켜야 할 것이 생긴다). 오류번호로 접속 기록(ops.req_log)을 찾는다.
   ★ 기록이다 — 지우려면 묻는다(ops.req_log 와 같은 취급). */
SET NOCOUNT ON;
GO
IF OBJECT_ID('ops.inquiry') IS NULL
CREATE TABLE ops.inquiry (
    inquiry_id  INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_inquiry PRIMARY KEY,
    때          DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    user_id     INT            NULL,
    아이디      NVARCHAR(50)   NULL,
    종류        NVARCHAR(20)   NOT NULL,          -- 오류
    무엇        NVARCHAR(100)  NULL,              -- 'AI 검색' · '단지 상세' …
    말          NVARCHAR(300)  NULL,              -- 카드에 보인 설명
    오류번호    VARCHAR(20)    NULL,
    단지코드    NVARCHAR(30)   NULL,
    화면        NVARCHAR(500)  NULL,
    내용        NVARCHAR(2000) NULL,              -- 사용자가 쓴 글(비워도 된다 — 오류 정보만으로도 남긴다)
    상태        NVARCHAR(20)   NOT NULL DEFAULT N'새로'
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_inquiry_때' AND object_id = OBJECT_ID('ops.inquiry'))
CREATE INDEX ix_inquiry_때 ON ops.inquiry (때 DESC);
GO
