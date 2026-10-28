/* 369 건축물대장 · 인허가 · 폐쇄대장 일정 — 사장님 "건대장은 매월 20일 기준으로 나와"(2026-10-28) → 기준일 20일 뒤 22일 02:00 부터 */
UPDATE ops.collect_schedule SET 주기 = 'monthly 22 02:00', 출처주기 = N'월간 · 매월 20일 기준(사장님 확인 2026-10-28)' WHERE 이름 = N'건축물대장 월 갱신';
UPDATE ops.collect_schedule SET 주기 = 'monthly 22 04:00', 출처주기 = N'월간 · 건축HUB 매월 20일 기준' WHERE 이름 = N'건축인허가';
UPDATE ops.collect_schedule SET 주기 = 'monthly 22 04:30', 출처주기 = N'월간 · 건축HUB 매월 20일 기준' WHERE 이름 = N'폐쇄대장';
SELECT 이름, 주기 FROM ops.collect_schedule WHERE 자료 IN (N'건축물대장', N'건축인허가', N'폐쇄대장');
