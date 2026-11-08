/* 407 (2026-11-08 사장님 "새벽 2~5시를 활용 · 그렇게만"): 무거운 발행(지도 마커 620만 + 큰 층 closed · sg_cmap · sg_cmap_s · sg_atch)을 매시에서 빼고 하루 두 번.
   03:20 — 새벽 정기(03:05 매시 발행과 안 겹치게 20분).  06:40 — 실거래가 06:10 에 들어온 뒤(아침 전에 마커의 최고가 · 거래 수를 맞춘다).
   매시 발행(cl-svc-hourly-par)은 상세 · 작은 층 · 주소 묶음만. 얻음: 낮에 DB 가 20분씩 바빠지는 구간이 없어진다. 잃음: 낮에 생긴 단지 · 거래가 지도 마커 · 검색에 다음 무거운 발행까지 늦다(상세는 매시). */
MERGE ops.collect_schedule AS d
USING (VALUES (N'무거운 발행(새벽) — 지도 마커 · 큰 층', N'서비스DB 발행', 'cl-svc-heavy-par', 'daily 03:20', N'파생', N'407 — 매시 발행에서 뺀 지도 마커 · 검색 큰 표를 새벽에', 'once', 1),
              (N'무거운 발행(실거래 뒤) — 지도 마커 · 큰 층', N'서비스DB 발행', 'cl-svc-heavy2-par', 'daily 06:40', N'파생', N'407 — 06:10 실거래가 들어온 뒤 지도 마커 최고가 · 거래 수 맞추기', 'once', 1))
      AS s (이름, 자료, 작업, 주기, 출처주기, 근거, 못돎이면, 켜짐)
ON d.작업 = s.작업
WHEN MATCHED THEN UPDATE SET 이름 = s.이름, 자료 = s.자료, 주기 = s.주기, 출처주기 = s.출처주기, 근거 = s.근거, 못돎이면 = s.못돎이면, 켜짐 = s.켜짐
WHEN NOT MATCHED THEN INSERT (이름, 자료, 작업, 주기, 출처주기, 근거, 못돎이면, 켜짐) VALUES (s.이름, s.자료, s.작업, s.주기, s.출처주기, s.근거, s.못돎이면, s.켜짐);
GO
SELECT 작업, 주기, 켜짐 FROM ops.collect_schedule WHERE 작업 IN ('cl-svc-heavy-par', 'cl-svc-heavy2-par', 'cl-svc-hourly-par');
