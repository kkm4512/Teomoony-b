/* 311_ask_log : AI 검색 질문 보관 (2026-10-22 사장님 "1. 질문저장" — AI 고도화용 실제 질문 모으기)
   ★ 로그인한 사용자만 AI 검색을 쓴다 → 아이디와 같이. IP·브라우저는 안 담는다.
   ★ 화면(AI 검색 안내 · 꼬리말)에 "질문 문장을 개선용으로 보관합니다" 라고 적는다 — 알리고 모은다.
   ★ 기록이다 — 지우려면 묻는다. */
SET NOCOUNT ON;
GO
IF OBJECT_ID('ops.ask_log') IS NULL
CREATE TABLE ops.ask_log (
    ask_id    BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT pk_ask_log PRIMARY KEY,
    때        DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    user_id   INT           NULL,
    아이디    NVARCHAR(50)  NULL,
    질문      NVARCHAR(500) NOT NULL,
    종류      NVARCHAR(20)  NULL,        -- 단지 · 지역순위
    해석      NVARCHAR(MAX) NULL,        -- 어떻게 알아들었나(JSON) — 못 알아들은 말이 고도화의 재료
    결과수    INT           NULL
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_ask_log_때' AND object_id = OBJECT_ID('ops.ask_log'))
CREATE INDEX ix_ask_log_때 ON ops.ask_log (때 DESC);
GO
