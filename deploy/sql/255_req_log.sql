/* 255. 접속 기록 (2026-10-21, 사장님 요청)
   "이용현황 저장할 때 사용자 IP나, 요청온 경로들도 저장 — 외부로는 안 보여주고 내부로만"
   결정: **90일 보관 · IP 통째로**(사장님이 고름).

   ★★ 이것은 `ops.usage_hour`(공개 집계)와 **다른 표다.** 섞지 않는다 —
     공개되는 것과 내부만 보는 것을 한 표에 두면 언젠가 공개 쪽으로 새어 나간다.

   ★ IP 는 개인정보다. 공개하지 않아도 **보관 자체로** 책임이 생긴다. 그래서
     ① 90일이 지나면 지운다(server.js 의 정리 타이머) ② 조회는 localhost 만
     ③ 하단에 수집 사실을 적는다(사장님 확인 대기).

   ★ `내부` 칸을 둔다. 내 QA·사장님 로컬 접속도 **버리지 않고 표시만** 한다 —
     usage_hour 에서는 아예 안 세지만(공개 수치라서), 여기서는 "무엇이 내 트래픽이고
     무엇이 남의 트래픽인가" 를 가릴 수 있어야 디버깅에 쓸모가 있다.
     지워 버리면 "이게 내 건가?" 를 영영 못 묻는다. */
IF SCHEMA_ID('ops') IS NULL EXEC('CREATE SCHEMA ops');
GO
IF OBJECT_ID('ops.req_log') IS NULL
CREATE TABLE ops.req_log (
    log_sk  BIGINT IDENTITY(1,1) NOT NULL,
    때      DATETIME2(0)   NOT NULL,   -- 한국시간(서버 시간대에 안 기댄다)
    ip      VARCHAR(45)    NULL,       -- IPv6 까지 들어갈 길이
    내부     BIT            NOT NULL CONSTRAINT df_req_log_내부 DEFAULT 0,
    경로     NVARCHAR(400)  NOT NULL,
    질의     NVARCHAR(400)  NULL,      -- querystring (키는 그대로, 값도 그대로)
    동작     NVARCHAR(40)   NULL,      -- usage_hour 와 같은 이름표. 없으면 NULL
    상태     SMALLINT       NULL,
    밀리     INT            NULL,      -- 응답까지 걸린 시간
    나라     VARCHAR(2)     NULL,      -- CF-IPCountry
    ua      NVARCHAR(300)  NULL,
    리퍼러   NVARCHAR(400)  NULL,
    CONSTRAINT pk_req_log PRIMARY KEY CLUSTERED (log_sk)
);
GO
/* 최근부터 보는 조회가 기본이다 */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_req_log_때')
CREATE INDEX ix_req_log_때 ON ops.req_log(때 DESC) INCLUDE (ip, 내부, 경로, 상태);
GO
/* "이 IP 가 또 왔나" 를 묻는 조회 */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_req_log_ip')
CREATE INDEX ix_req_log_ip ON ops.req_log(ip, 때 DESC);
GO
PRINT '255 완료 - ops.req_log';
