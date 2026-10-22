/* ============================================================
   313_my : 내 정보 — 관심 단지 · 알림함 (2026-10-22 사장님 "로그인 기능이 있으니 관심 단지 · 내정보 · 문의 답변 오면 사이트 안 수신함")
   ★ 회원가입은 보류(사장님 20:52) — 지금 있는 계정(meta.app_user)만 쓴다.
   ★ 둘 다 사람이 남긴 **기록**이다(ops). 지우지 않는다:
     - 관심 단지를 빼면 뺀때 를 적는다(행은 남는다). 다시 넣으면 뺀때 를 비우고 넣은때 를 새로.
     - 알림은 읽으면 읽은때 를 적는다.
   ★ 외부 메일은 쓰지 않는다(사장님 "메일 API 말고 사이트 자체 수신함").
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
IF OBJECT_ID('ops.fav_complex') IS NULL
CREATE TABLE ops.fav_complex (
    user_id    INT           NOT NULL,
    complex_id INT           NOT NULL,
    넣은때     DATETIME2(0)  NOT NULL CONSTRAINT df_fav_in DEFAULT SYSDATETIME(),
    뺀때       DATETIME2(0)  NULL,
    CONSTRAINT pk_fav_complex PRIMARY KEY CLUSTERED (user_id, complex_id)
);
IF OBJECT_ID('ops.notice') IS NULL
CREATE TABLE ops.notice (
    notice_id  INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_notice PRIMARY KEY CLUSTERED,
    user_id    INT           NOT NULL,
    때         DATETIME2(0)  NOT NULL CONSTRAINT df_notice_t DEFAULT SYSDATETIME(),
    종류       NVARCHAR(20)  NOT NULL,          -- 문의답변
    제목       NVARCHAR(200) NOT NULL,
    내용       NVARCHAR(1000) NULL,
    inquiry_id INT           NULL,
    읽은때     DATETIME2(0)  NULL
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_notice_user')
    CREATE INDEX ix_notice_user ON ops.notice (user_id, 읽은때) INCLUDE (때);
GO
/* 이미 답이 달린 문의(오늘 #1 등)에도 알림 한 줄 — 같은 문의에 같은 답변 때의 알림이 없을 때만 */
INSERT INTO ops.notice (user_id, 때, 종류, 제목, 내용, inquiry_id)
SELECT q.user_id, q.답변때, N'문의답변', N'문의 #' + CAST(q.inquiry_id AS NVARCHAR(12)) + N' 에 답변이 달렸습니다',
       LEFT(q.답변, 300), q.inquiry_id
  FROM ops.inquiry q
 WHERE q.답변 IS NOT NULL AND q.user_id IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM ops.notice n WHERE n.inquiry_id = q.inquiry_id AND n.종류 = N'문의답변');
SELECT 알림 = (SELECT COUNT(*) FROM ops.notice), 관심 = (SELECT COUNT(*) FROM ops.fav_complex);
