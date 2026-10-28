/* 370 (2026-10-28) 상가 분기 파일 확인(semas_check.py · cl-semas-par) 켜기 — 첫 시험: 새 것 없음 → 종료코드 3(건너뜀) 확인함 */
UPDATE ops.collect_schedule SET 켜짐 = 1,
       메모 = N'10-28 켬 · 새 판이면 받아 분기 갱신(새것이 이김 · 빠진 점포 닫기만 · 덜 온 파일이면 멈춤)'
 WHERE 이름 = N'상가 분기 파일' AND 작업 = 'cl-semas-par';
SELECT 이름, 켜짐, 주기, 못돎이면, 메모 FROM ops.collect_schedule WHERE 이름 = N'상가 분기 파일';
