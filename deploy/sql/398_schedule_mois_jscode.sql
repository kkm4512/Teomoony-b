/* 398 행안부 행정동·법정동 코드 변경 게시판 매주 보기 — 일정 (2026-10-31)
   작업 cl-mois-jscode-par = etl/mois_jscode_watch.py — 새 판(jscodeYYYYMMDD(말소코드포함).zip)이 올라왔으면 받아 넣고(395)
   옛→새 법정동(396) · 행정동 경계 연결(397)을 다시 만든다. 새 판이 없으면 종료코드 3(건너뜀).
   행안부는 행정구역이 바뀔 때마다 글을 올린다(2026: 2.25 · 3.1 · 3.25 · 7.1 · 7.20 · 9.30 · 10.12 · 10.30) → 주 1회면 늦어도 1주. */
SET NOCOUNT ON;
MERGE ops.collect_schedule AS d
USING (VALUES (N'행정동·법정동 코드(행안부)', N'지역 코드', 'cl-mois-jscode-par', 'weekly mon 05:20', N'바뀔 때마다(해마다 수 차례)',
               N'행정안전부 › 주민등록·인감 › 행정기관(행정동) 및 관할구역(법정동) 코드 변경내역 알림', 'once', 1))
      AS s (이름, 자료, 작업, 주기, 출처주기, 근거, 못돎이면, 켜짐)
ON d.작업 = s.작업
WHEN MATCHED THEN UPDATE SET 이름 = s.이름, 자료 = s.자료, 주기 = s.주기, 출처주기 = s.출처주기, 근거 = s.근거, 못돎이면 = s.못돎이면, 켜짐 = s.켜짐
WHEN NOT MATCHED THEN INSERT (이름, 자료, 작업, 주기, 출처주기, 근거, 못돎이면, 켜짐) VALUES (s.이름, s.자료, s.작업, s.주기, s.출처주기, s.근거, s.못돎이면, s.켜짐);
SELECT 작업, 주기, 켜짐 FROM ops.collect_schedule WHERE 작업 = 'cl-mois-jscode-par';
