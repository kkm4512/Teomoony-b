/* 422 (2026-11-20 사장님 "ㄱㄱ"): 실거래 매달 바로잡기 — etl/rtms_monthly.py(최근 24개월 다시 받기 → 원천 ↔ 적재 대조 → 사라진 줄 격리(420) → 단지 상세 다시 담기).
   매일 받기(rtms_recent)는 최근 3개월만 보아 그보다 늦은 변경(늦은 동 · 등기일 · 지번 변경 · 정정 · 철회)을 못 본다.
   매달 2일 00:40 = 00:10 rtms_recent 뒤 · 03:10 앞(약 30~40분). 작업 이름은 etl/_jobs_linux.json 의 cl-rtms-monthly-par. */
MERGE ops.collect_schedule AS d
USING (VALUES (N'실거래 매달 바로잡기(최근 24개월)', N'실거래', 'cl-rtms-monthly-par', 'monthly 2 00:40', N'파생',
               N'422 — 다시 받기 · 원천 대조 · 사라진 줄 격리 · 상세 다시 담기', 'once', 1))
      AS s (이름, 자료, 작업, 주기, 출처주기, 근거, 못돎이면, 켜짐)
ON d.작업 = s.작업
WHEN MATCHED THEN UPDATE SET 이름 = s.이름, 자료 = s.자료, 주기 = s.주기, 출처주기 = s.출처주기, 근거 = s.근거, 못돎이면 = s.못돎이면, 켜짐 = s.켜짐
WHEN NOT MATCHED THEN INSERT (이름, 자료, 작업, 주기, 출처주기, 근거, 못돎이면, 켜짐) VALUES (s.이름, s.자료, s.작업, s.주기, s.출처주기, s.근거, s.못돎이면, s.켜짐);
GO
SELECT 작업, 주기, 켜짐 FROM ops.collect_schedule WHERE 작업 IN ('cl-rtms-monthly-par', 'cl-rtms-recent-par', 'zq-dqm-rules-par');
