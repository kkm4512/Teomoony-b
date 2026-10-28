/* 366 수집 일정 · 실행 기록 (2026-10-28 사장님 "스케줄 적용하고, 스케줄이 도는 것들 로그 — 돌았나 안 돌았나, 안 돌았으면 왜")
   ★ ops.collect_schedule = 무엇을 언제 받나(자료 · 작업 · 주기 · 출처가 바뀌는 주기와 근거).
   ★ ops.collect_run      = 한 번 돌 때마다 한 줄 — 예정 · 놓음 · 시작 · 끝 · 상태(놓음/도는중/성공/실패/건너뜀/못돎) · 이유 · 종료코드 · 로그.
     '못돎' 은 작업이 스스로 못 적는다(시작도 못 했으니) → etl/collect_cron.py 가 일정과 기록을 맞대 적는다.
   ★ 시각은 한국시간(req_log 와 같게). 기록은 지우지 않는다(ops). */
IF OBJECT_ID('ops.collect_schedule') IS NULL
CREATE TABLE ops.collect_schedule (
    schedule_id INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_collect_schedule PRIMARY KEY,
    이름        NVARCHAR(60)  NOT NULL CONSTRAINT uq_collect_schedule UNIQUE,
    자료        NVARCHAR(40)  NOT NULL,            -- meta.coverage 의 자료 이름과 같게(건축물대장 · 실거래 …)
    작업        VARCHAR(80)   NOT NULL,            -- _jobs_extra.json 의 작업 이름(_queue/<작업>.job)
    주기        VARCHAR(60)   NOT NULL,            -- hourly :05 · every 6h :35 · daily 04:10 · weekly mon 03:30 · monthly 3 02:00 · quarterly 1,4,7,10 5 03:00 · yearly 06-05 03:00
    출처주기    NVARCHAR(120) NULL,                -- 출처가 새로 내는 때(사람이 읽는 말)
    근거        NVARCHAR(300) NULL,                -- 그 주기의 근거(출처 페이지 주소 · 확인일)
    못돎이면    VARCHAR(10)   NOT NULL CONSTRAINT df_cs_catch DEFAULT 'once',   -- once = 켜지면 한 번 따라잡기 · skip = 다음 차례까지 기다림
    켜짐        BIT           NOT NULL CONSTRAINT df_cs_on DEFAULT 1,
    메모        NVARCHAR(300) NULL,
    만든때      DATETIME2(0)  NOT NULL CONSTRAINT df_cs_at DEFAULT SYSDATETIME()
);
GO
IF OBJECT_ID('ops.collect_run') IS NULL
CREATE TABLE ops.collect_run (
    run_id      BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT pk_collect_run PRIMARY KEY,
    schedule_id INT           NULL,
    이름        NVARCHAR(60)  NOT NULL,
    작업        VARCHAR(80)   NOT NULL,
    예정        DATETIME2(0)  NOT NULL,
    놓음        DATETIME2(0)  NULL,
    시작        DATETIME2(0)  NULL,
    끝          DATETIME2(0)  NULL,
    상태        NVARCHAR(10)  NOT NULL,             -- 놓음 · 도는중 · 성공 · 실패 · 건너뜀 · 못돎
    이유        NVARCHAR(600) NULL,
    종료코드    INT           NULL,
    초          INT           NULL,
    로그        NVARCHAR(200) NULL
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_collect_run_sch')
CREATE INDEX ix_collect_run_sch ON ops.collect_run (schedule_id, 예정 DESC) INCLUDE (상태, 끝);
GO
SELECT 일정 = (SELECT COUNT(*) FROM ops.collect_schedule), 기록 = (SELECT COUNT(*) FROM ops.collect_run);
GO
/* 다음 예정(collect_cron 이 바퀴마다 적는다 — 화면이 주기 글을 따로 풀지 않게) */
IF COL_LENGTH('ops.collect_schedule', '다음') IS NULL ALTER TABLE ops.collect_schedule ADD 다음 DATETIME2(0) NULL, 확인 DATETIME2(0) NULL;
GO
