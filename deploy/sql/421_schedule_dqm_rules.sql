/* 421 (2026-11-19 사장님 "추천대로 ㄱ" · DQM ③): 규칙 표(etl/dqm_rules.yaml)로 서울 실거래 전체를 매일 잰다 — etl/dqm_rules.py run(약 1분).
   07:50 = 06:10 실거래 받기 · 07:20 DQM 스냅샷 뒤. 원본은 읽기만 · 결과는 ops.dqm_rule_run / _stat / _hit / ops.dqm_grade_stat. 화면: DQM 탭 ③.
   작업 이름은 etl/_jobs_linux.json 의 zq-dqm-rules-par(_jobs_extra.json 은 받기 때 깃 판으로 되돌아간다). */
MERGE ops.collect_schedule AS d
USING (VALUES (N'DQM ③ — 실거래 규칙 검사', N'실험(DQM)', 'zq-dqm-rules-par', 'daily 07:50', N'파생', N'421 — 규칙 표 18개 · 줄마다 걸린 규칙 · 등급 A/B/C/격리', 'once', 1))
      AS s (이름, 자료, 작업, 주기, 출처주기, 근거, 못돎이면, 켜짐)
ON d.작업 = s.작업
WHEN MATCHED THEN UPDATE SET 이름 = s.이름, 자료 = s.자료, 주기 = s.주기, 출처주기 = s.출처주기, 근거 = s.근거, 못돎이면 = s.못돎이면, 켜짐 = s.켜짐
WHEN NOT MATCHED THEN INSERT (이름, 자료, 작업, 주기, 출처주기, 근거, 못돎이면, 켜짐) VALUES (s.이름, s.자료, s.작업, s.주기, s.출처주기, s.근거, s.못돎이면, s.켜짐);
GO
SELECT 작업, 주기, 켜짐, 다음 FROM ops.collect_schedule WHERE 작업 LIKE 'z%dqm%';
