/* 408 (2026-11-11 DQM 실험 · 사장님 ㄱㄱ): 서울 3구(강남 · 송파 · 노원) × 최근 3개월 × 아파트 매매 · 전월세 스냅샷을 매일 받아 어제와 비교(I/U/D/애매).
   07:20 = 06:10 실거래가 들어온 뒤. 읽기만(적재DB 에 안 씀) · 파일은 data/dqm/snap/. 실험이 끝나면 켜짐 = 0 으로 끈다. */
MERGE ops.collect_schedule AS d
USING (VALUES (N'DQM 실험 — 실거래 스냅샷', N'실험(DQM)', 'zt-dqm-snap-par', 'daily 07:20', N'파생', N'408 — 묶음(종목×시군구×월) 원천 그대로 + 건수 · 해시', 'once', 1),
              (N'DQM 실험 — 어제와 비교(I/U/D)', N'실험(DQM)', 'zt-dqm-diff-par', 'daily 07:30', N'파생', N'408 — 줄 전체 해시 개수 비교 → 정체성 해시 짝짓기', 'once', 1))
      AS s (이름, 자료, 작업, 주기, 출처주기, 근거, 못돎이면, 켜짐)
ON d.작업 = s.작업
WHEN MATCHED THEN UPDATE SET 이름 = s.이름, 자료 = s.자료, 주기 = s.주기, 출처주기 = s.출처주기, 근거 = s.근거, 못돎이면 = s.못돎이면, 켜짐 = s.켜짐
WHEN NOT MATCHED THEN INSERT (이름, 자료, 작업, 주기, 출처주기, 근거, 못돎이면, 켜짐) VALUES (s.이름, s.자료, s.작업, s.주기, s.출처주기, s.근거, s.못돎이면, s.켜짐);
GO
SELECT 작업, 주기, 켜짐 FROM ops.collect_schedule WHERE 작업 LIKE 'zt-dqm%';
