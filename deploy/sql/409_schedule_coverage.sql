/* 409 (2026-11-10) 받은 범위표(339) 다시 세기를 매시 :50 한 번으로
   전에는 작업 감시기가 z- 아닌 작업이 성공할 때마다 z-coverage-par 를 걸었다(10-24 '약 20초').
   전국으로 늘어 한 번에 3~11분 · 11-10 하루 8번 · 누적 982번 — 적재DB CPU 상위.
   이제 z-coverage-par 는 etl/coverage_gate.py --gap 60(60분 안이면 건너뜀 = 3), 이 일정(cl-coverage-par = --gap 0)이 늘 센다.
   → 범위표는 늦어도 한 시간 안에 맞고, 한 시간에 대개 한 번만 돈다. */
MERGE ops.collect_schedule t
USING (VALUES (N'받은 범위표 다시 세기', N'운영', 'cl-coverage-par', 'hourly :50', N'우리 쪽',
               N'2026-11-10 적재 뒤마다 걸던 범위표(339)를 매시 한 번으로 — 적재DB CPU', 'skip', CAST(1 AS BIT)))
      s (이름, 자료, 작업, 주기, 출처주기, 근거, 못돎이면, 켜짐)
   ON t.이름 = s.이름
WHEN NOT MATCHED THEN INSERT (이름, 자료, 작업, 주기, 출처주기, 근거, 못돎이면, 켜짐) VALUES (s.이름, s.자료, s.작업, s.주기, s.출처주기, s.근거, s.못돎이면, s.켜짐);
SELECT schedule_id, 이름, 작업, 주기, 켜짐 FROM ops.collect_schedule WHERE 작업 = 'cl-coverage-par';
