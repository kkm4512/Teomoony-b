/* 403 실거래 받기 기록 · 3시간마다 (2026-11-01 사장님 "n시간에 한 번씩 수집해 보는 걸로 바꾸고, 로그 보고 시간대를 측정")
   ★ 국토부 실거래 공개 API 가 전날 신고분을 **하루 중 몇 시에** 올리는지 모른다(안내는 '익일 공개'뿐) → 3시간마다 최근 3개월을 받고
     받을 때마다 새로 들어온 건수 · 해제 · 종류별 · 가장 최근 계약일을 ops.rtms_fetch_log 에 남긴다. 며칠 쌓이면 새 건이 들어오는 시간대를 보고
     수집 시각을 다시 정한다.
   ★ 호출량: 시군구 255 × 3개월 = 종류(API)마다 765회 × 하루 8번 = 6,120회 + 매달 1일 1년치 3,060회 — 개발 계정 하루 10,000회 안.
   ★ 새로 들어온 게 없으면 단지 다시 잇기(19분 남짓)를 건너뛴다. */
SET NOCOUNT ON;
GO
IF OBJECT_ID('ops.rtms_fetch_log') IS NULL
CREATE TABLE ops.rtms_fetch_log (
    id          INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_rtms_fetch_log PRIMARY KEY,
    시작        DATETIME2(0)  NOT NULL,     -- 한국 시각
    끝          DATETIME2(0)  NULL,
    개월        TINYINT       NOT NULL,
    받기초      INT           NULL,
    새로        BIGINT        NULL,
    해제        INT           NULL,
    종류별      NVARCHAR(1000) NULL,        -- '아파트매매 +12 · 분양권 +3 …'
    최근계약    CHAR(8)       NULL,
    실패        INT           NULL,
    다시잇기    BIT           NULL
);
GO
UPDATE ops.collect_schedule
   SET 주기 = 'every 3h :10', 출처주기 = N'매일(익일 공개 · 올라오는 시각 모름 — 3시간마다 받아 재는 중)',
       근거 = N'data.go.kr 15126468 외 RTMS · rt.molit.go.kr "실시간 취합 후 익일 공개" · 403 받기 기록(ops.rtms_fetch_log)으로 올라오는 시각을 잰다(11-01 사장님)'
 WHERE 작업 = 'cl-rtms-recent-par';
SELECT 작업, 주기, 출처주기 FROM ops.collect_schedule WHERE 작업 = 'cl-rtms-recent-par';
GO
