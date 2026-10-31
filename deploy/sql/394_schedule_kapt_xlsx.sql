/* 394 K-apt 자료실 관리비 엑셀(393) 매주 받기 — 일정 (2026-10-31)
   작업 cl-kapt-xlsx-par = etl/kapt_cost_xlsx_load.py — 자료실 연도별 글(2015 ~ 올해)의 새 파일만 받아 넣는다(이름 앞 날짜가 바뀐 것).
   K-apt 는 금요일에 다시 올린다(10-23 · 10-30 실측) → 토요일 05:40. 새 파일이 없으면 종료코드 3(건너뜀). */
SET NOCOUNT ON;
MERGE ops.collect_schedule AS d
USING (VALUES (N'관리비 엑셀(K-apt 자료실)', N'관리비', 'cl-kapt-xlsx-par', 'weekly sat 05:40', N'주 1회(금요일 게시)', N'K-apt 소통마당 › 자료실 › 관리비정보(연도별 엑셀)', 'once', 1))
      AS s (이름, 자료, 작업, 주기, 출처주기, 근거, 못돎이면, 켜짐)
ON d.작업 = s.작업
WHEN MATCHED THEN UPDATE SET 이름 = s.이름, 자료 = s.자료, 주기 = s.주기, 출처주기 = s.출처주기, 근거 = s.근거, 못돎이면 = s.못돎이면, 켜짐 = s.켜짐
WHEN NOT MATCHED THEN INSERT (이름, 자료, 작업, 주기, 출처주기, 근거, 못돎이면, 켜짐) VALUES (s.이름, s.자료, s.작업, s.주기, s.출처주기, s.근거, s.못돎이면, s.켜짐);
SELECT 작업, 주기, 켜짐 FROM ops.collect_schedule WHERE 작업 = 'cl-kapt-xlsx-par';
