/* 378 (2026-10-28 21:06) 토지특성 '없음' 표시 잘못 적힌 것 지우기 — 원본이 아니라 우리 '물어봤는데 비었음' 기록(파생)
   전국 첫 실행(load_land_char --complex-min-hhld 20)이 필지 순서대로 12(전남광주통합특별시)부터 불렀는데, VWorld 토지특성은 아직 새 코드를 몰라
   'response' 봉투 0건 → 1,499 필지가 '없음' 으로 적혔다(그대로 두면 다시 안 묻는다). 12 는 이번 실행 전에는 한 번도 안 불렀다(지우는 것은 전부 이번 것). */
SELECT 지울것 = COUNT(*) FROM silver.land_char_none WHERE pnu LIKE '12%';
DELETE FROM silver.land_char_none WHERE pnu LIKE '12%';
SELECT 남은12 = COUNT(*) FROM silver.land_char_none WHERE pnu LIKE '12%';
