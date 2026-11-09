/* 408 (2026-11-09 사장님 "각 오픈 API가 잘되는지, 배치 잘돌았는지, 이용현황 하루에 한번 정리해서 슬랙으로") 일일 리포트
   etl/daily_report.py — ① 오픈 API 키 38곳 가벼운 호출(정상 · 키문제 · 한도 · 응답이상) + 만료 45일 전 경고
   ② ops.collect_run 지난 24시간(실패 · 못돎 · 6시간 넘게 도는중 · 예정 지나도 안 걸림) ③ 감시기 · 웹 · teomoony.com 응답
   ④ 어제 이용 현황(/api/usage?day= — 사람만 · 운영자 뺌) + 바깥 5xx · API 응답 95% 시간. 슬랙 = .env SLACK_WEBHOOK_URL. */
MERGE ops.collect_schedule t
USING (VALUES (N'일일 리포트(슬랙)', N'운영', 'cl-daily-report-par', 'daily 08:30', N'우리 쪽',
               N'2026-11-09 사장님 요청 — API 상태 · 배치 결과 · 이용 현황을 매일 아침 슬랙으로', 'skip', CAST(1 AS BIT)))
      s (이름, 자료, 작업, 주기, 출처주기, 근거, 못돎이면, 켜짐)
   ON t.이름 = s.이름
WHEN NOT MATCHED THEN INSERT (이름, 자료, 작업, 주기, 출처주기, 근거, 못돎이면, 켜짐) VALUES (s.이름, s.자료, s.작업, s.주기, s.출처주기, s.근거, s.못돎이면, s.켜짐);
SELECT schedule_id, 이름, 작업, 주기, 켜짐 FROM ops.collect_schedule WHERE 작업 = 'cl-daily-report-par';
