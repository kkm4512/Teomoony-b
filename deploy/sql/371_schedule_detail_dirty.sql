/* 371 (2026-10-28 사장님 "너판단으로 ㄱㄱ") 상세 다시(밀린 것) — svc.detail_dirty 를 뒤에서 비운다.
   적히는 때: 매시 마커의 실거래 칸이 바뀐 단지(매시 발행이 3,000곳까지 바로 처리 · 넘치면 여기서) · 상가 새 판(발행된 상세 전부 · semas_check).
   6시간마다 최대 5시간 30분 · 표가 비었으면 종료코드 3(건너뜀). 실거래 바뀜이 늘 먼저. */
MERGE ops.collect_schedule t
USING (VALUES (N'상세 다시(밀린 것)', N'서비스DB 상세', 'cl-svc-dirty-par', 'every 6h :50', N'우리 쪽(원천 바뀜 뒤)',
               N'svc.detail_dirty — 실거래 다시 잇기 · 상가 새 판 뒤 발행된 상세를 지금 서버 응답으로 다시 담음(값 안 고침)', 'skip', CAST(1 AS BIT)))
      s (이름, 자료, 작업, 주기, 출처주기, 근거, 못돎이면, 켜짐)
   ON t.이름 = s.이름
WHEN NOT MATCHED THEN INSERT (이름, 자료, 작업, 주기, 출처주기, 근거, 못돎이면, 켜짐) VALUES (s.이름, s.자료, s.작업, s.주기, s.출처주기, s.근거, s.못돎이면, s.켜짐);
SELECT schedule_id, 이름, 작업, 주기, 켜짐 FROM ops.collect_schedule WHERE 작업 = 'cl-svc-dirty-par';
