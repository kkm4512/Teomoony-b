/* 392 관리비 수집 일정 켜기 (2026-10-31 사장님 "ㅇㅋ")
   작업 cl-kapt-cost-par = etl/kapt_cost_monthly.py — 매달 3일 04:00, 이번 달 기준 두 달 전(M-2) 한 달을 전국으로.
   ★ 이미 받은 달이면(최근 12달 가장 많이 받은 달의 95% 이상) 건너뜀(종료코드 3) — 11월 3일 목표 9월분은 10-29 에 전국을 받아 두어 건너뛴다.
   ★ 하루 한도에 걸리면 종료코드 4(알림) — 받은 데까지 두고 멈춘다. */
SET NOCOUNT ON;
UPDATE ops.collect_schedule SET 켜짐 = 1 WHERE 작업 = 'cl-kapt-cost-par';
SELECT 켬 = @@ROWCOUNT, 다음 = (SELECT CONVERT(VARCHAR(16), 다음, 120) FROM ops.collect_schedule WHERE 작업 = 'cl-kapt-cost-par'),
       주기 = (SELECT 주기 FROM ops.collect_schedule WHERE 작업 = 'cl-kapt-cost-par');
