/* 367 수집 일정 첫 줄들 (2026-10-28) — 지금 바로 돌릴 수 있는 것부터. 나머지는 출처 주기 확인 · 전국 판 작업이 준비되면 더한다. */
MERGE ops.collect_schedule AS d
USING (VALUES
 (N'서비스DB 매시 발행', N'서비스DB', 'cl-svc-hourly-par', 'hourly :05', N'적재DB 가 바뀔 때마다', N'svc_cron(10-24 사장님 "1시간에 한 번") 를 옮김', 'skip'),
 (N'매칭 테이블(nm)', N'서비스DB', 'nm-build-par', 'every 6h :35', N'원천 표가 바뀔 때', N'10-28 매시 → 6시간(C 드라이브 · 원천은 월 1회 이하)', 'skip'),
 (N'법정동코드', N'법정동코드', 'cl-lawd-par', 'weekly mon 03:30', N'수시(읍 승격 · 동 통합 — 예: 구지읍 2026-09-30)', N'행안부 StanReginCd(15077871)', 'once'),
 (N'실거래 최근 3개월', N'실거래', 'cl-rtms-recent-par', 'daily 03:10', N'매일(신고 30일 안 · 해제 · 정정)', N'국토부 RTMS', 'once')
) AS s (이름, 자료, 작업, 주기, 출처주기, 근거, 못돎이면)
ON d.이름 = s.이름
WHEN MATCHED THEN UPDATE SET 자료 = s.자료, 작업 = s.작업, 주기 = s.주기, 출처주기 = s.출처주기, 근거 = s.근거, 못돎이면 = s.못돎이면
WHEN NOT MATCHED THEN INSERT (이름, 자료, 작업, 주기, 출처주기, 근거, 못돎이면) VALUES (s.이름, s.자료, s.작업, s.주기, s.출처주기, s.근거, s.못돎이면);
SELECT schedule_id, 이름, 작업, 주기 FROM ops.collect_schedule ORDER BY schedule_id;
