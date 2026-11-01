/* 404 (2026-11-01) 서비스DB 분리 2묶음 — 무거운 주소 묶음(분양·청약 · 경계 · 학원 · 학교 · 유치원 · 어린이집 · 신축)을 6시간마다.
   묶음마다 지문(원천이 그대로면 건너뜀) · 자기 주기(every)가 따로 있다 — 이 일정은 '들여다보는' 주기일 뿐. */
MERGE ops.collect_schedule AS d
USING (VALUES (N'서비스DB 주소 묶음(무거운 것)', N'파생(서비스DB)', 'cl-svc-pub-par', 'every 6h :40', N'파생',
               N'svc_pub_urls.py --heavy — 같은 서버 · 같은 주소의 응답을 svc.resp_pub 에(404)', 'once', 1))
      AS s (이름, 자료, 작업, 주기, 출처주기, 근거, 못돎이면, 켜짐)
ON d.작업 = s.작업
WHEN MATCHED THEN UPDATE SET 이름 = s.이름, 자료 = s.자료, 주기 = s.주기, 출처주기 = s.출처주기, 근거 = s.근거, 못돎이면 = s.못돎이면, 켜짐 = s.켜짐
WHEN NOT MATCHED THEN INSERT (이름, 자료, 작업, 주기, 출처주기, 근거, 못돎이면, 켜짐) VALUES (s.이름, s.자료, s.작업, s.주기, s.출처주기, s.근거, s.못돎이면, s.켜짐);
GO
SELECT 작업, 주기, 켜짐 FROM ops.collect_schedule WHERE 작업 = 'cl-svc-pub-par';
GO
