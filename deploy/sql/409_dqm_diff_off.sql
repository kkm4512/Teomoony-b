/* 409 (2026-11-13): DQM 비교를 스냅샷 작업 안으로(zt-dqm-snap-par = snap --diff). 따로 걸던 비교(07:30)는 끈다 —
   PC 가 아침에 꺼져 있다 밤에 켜지면 두 줄이 함께 밀려 걸려 비교가 스냅샷보다 먼저 돌았다(11-12 22:02). */
UPDATE ops.collect_schedule SET 켜짐 = 0 WHERE 작업 = 'zt-dqm-diff-par';
SELECT 작업, 주기, 켜짐 FROM ops.collect_schedule WHERE 작업 LIKE 'zt-dqm%';
