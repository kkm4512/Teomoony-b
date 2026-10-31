/* 400 평단가(399) 매일 다시 만들기 — 일정 (2026-11-01)
   작업 cl-pyeong-par = ms_q.py 399_pyeong_run.sql — 실거래 적재(새벽) 뒤 07:10. 30초 남짓(시험 공간 2.3백만 줄 기준). */
SET NOCOUNT ON;
MERGE ops.collect_schedule AS d
USING (VALUES (N'평단가(실거래 중앙값)', N'실거래', 'cl-pyeong-par', 'daily 07:10', N'실거래 적재 뒤 매일', N'gold.usp_build_pyeong_price (399)', 'once', 1))
      AS s (이름, 자료, 작업, 주기, 출처주기, 근거, 못돎이면, 켜짐)
ON d.작업 = s.작업
WHEN MATCHED THEN UPDATE SET 이름 = s.이름, 자료 = s.자료, 주기 = s.주기, 출처주기 = s.출처주기, 근거 = s.근거, 못돎이면 = s.못돎이면, 켜짐 = s.켜짐
WHEN NOT MATCHED THEN INSERT (이름, 자료, 작업, 주기, 출처주기, 근거, 못돎이면, 켜짐) VALUES (s.이름, s.자료, s.작업, s.주기, s.출처주기, s.근거, s.못돎이면, s.켜짐);
SELECT 작업, 주기, 켜짐 FROM ops.collect_schedule WHERE 작업 = 'cl-pyeong-par';
