/* 383 청약공고 수집 일정 켜기 (2026-10-29) — 전국(load_applyhome --nation · applyhome_addr) · 작업 cl-applyhome-par = applyhome_cron.py */
UPDATE ops.collect_schedule SET 켜짐 = 1, 근거 = N'data.go.kr 15098547 · 15098905 — 전국(2026-10-29), 주소는 마스터 이름 글자 그대로 · 하나일 때만' WHERE 작업 = 'cl-applyhome-par';
SELECT x = (SELECT STRING_AGG(CONCAT(이름, ' ', 작업, ' ', 주기, ' 켜짐', CAST(켜짐 AS INT)), ' | ') FROM ops.collect_schedule WHERE 작업 = 'cl-applyhome-par');
