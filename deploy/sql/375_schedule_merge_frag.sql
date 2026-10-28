/* 375 (2026-10-28 사장님 "규칙도 정책에 동기화하고 스케줄 로직에 포함돼야 해") 단지 조각 묶기(정책 2-1) — 건축물대장 월 갱신(22일 02:00) 다음 날.
   새로 묶을 게 없으면 종료코드 3(건너뜀). 실거래 한 필지 여러 단지 규칙(372)은 매칭 프로시저 안이라 매일 03:10 재매칭에 이미 들어 있다. */
MERGE ops.collect_schedule t
USING (VALUES (N'단지 조각 묶기', N'우리 단지(대장 조각)', 'cl-merge-frag-par', 'monthly 23 05:10', N'우리 쪽(건축물대장 월 갱신 뒤)',
               N'정책 2-1 · 373/374 — 같은 필지·부속지번 + 같은 허가일/도로명 · 보류(빼기만) · 지우지 않음 · 기록', 'once', CAST(1 AS BIT)))
      s (이름, 자료, 작업, 주기, 출처주기, 근거, 못돎이면, 켜짐)
   ON t.이름 = s.이름
WHEN NOT MATCHED THEN INSERT (이름, 자료, 작업, 주기, 출처주기, 근거, 못돎이면, 켜짐) VALUES (s.이름, s.자료, s.작업, s.주기, s.출처주기, s.근거, s.못돎이면, s.켜짐);
SELECT schedule_id, 이름, 작업, 주기, 못돎이면, 켜짐 FROM ops.collect_schedule WHERE 작업 IN ('cl-merge-frag-par', 'cl-rtms-recent-par', 'cl-hub-month-par');
