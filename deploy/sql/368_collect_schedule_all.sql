/* 368 수집 일정 확정본 (2026-10-28 12:00 사장님 "확정해")
   ★ 출처 주기 근거 = data.go.kr 각 자료 페이지의 업데이트 주기 · 수정일 · 차기 등록 예정일, 법령(공시 기한), 2026-10-28 확인.
   ★ 켜짐 0 = 작업이 아직 전국 판이 아니거나(일부 지역만 받음) 바뀐 것만 받는 작업이 없음 — 수집 현황에 '꺼짐'으로 보인다. 준비되면 하나씩 켠다. */
MERGE ops.collect_schedule AS d
USING (VALUES
 (N'실거래 1년치 맞춰보기', N'실거래', 'cl-rtms-year-par', 'monthly 1 02:10', N'신고 30일 · 해제 · 정정이 몇 달 뒤에도', N'data.go.kr 15126468 외 · rt.molit.go.kr "익일 공개 · 계약일 기준"', 'once', 1),
 (N'청약공고 · 경쟁률', N'청약공고', 'cl-applyhome-par', 'daily 05:10', N'실시간(공고 수시)', N'data.go.kr 15098547 · 15098905', 'once', 0),
 (N'건축물대장 월 갱신', N'건축물대장', 'cl-hub-month-par', 'monthly 5 02:00', N'월간', N'data.go.kr 15134735 BldRgstHubService 월간', 'once', 0),
 (N'건축인허가', N'건축인허가', 'cl-permit-par', 'monthly 5 04:00', N'월간', N'data.go.kr 15136267', 'once', 0),
 (N'폐쇄대장', N'폐쇄대장', 'cl-closed-par', 'monthly 5 04:30', N'월간', N'data.go.kr 15137093', 'once', 0),
 (N'K-apt 단지정보', N'K-apt', 'cl-kapt-par', 'weekly tue 04:00', N'실시간(파일은 주간)', N'data.go.kr 15057332 · 15058453 · 15073271', 'once', 0),
 (N'관리비', N'관리비', 'cl-kapt-cost-par', 'monthly 3 04:00', N'다음 달 말일까지 올림(공동주택관리법 시행령 23조 8항)', N'data.go.kr 15057937 · 15059469', 'once', 0),
 (N'토지이동 → 필지', N'토지이동', 'cl-landmove-par', 'weekly thu 04:00', N'수시', N'data.go.kr 15123974 · 15123899', 'once', 0),
 (N'토지이용계획 · 용도지역', N'토지이용계획', 'cl-landuse-par', 'quarterly 1,4,7,10 15 03:00', N'파일 분기 · API 실시간', N'data.go.kr 15123973 · 15123895', 'once', 0),
 (N'공동주택가격', N'공동주택가격', 'cl-hsprc-par', 'quarterly 5,10 5 03:00', N'4월 30일 공시 + 9월 30일 추가(6/1 기준)', N'부동산 가격공시법 시행령 43조', 'once', 0),
 (N'개별공시지가 · 토지특성', N'토지특성', 'cl-landchar-par', 'quarterly 6,11 5 03:00', N'5월 31일 공시 + 10월 31일 추가', N'부동산 가격공시법 시행령 21조 · data.go.kr 15123549', 'once', 0),
 (N'상가 분기 파일', N'상가', 'cl-semas-par', 'daily 06:10', N'분기 · 분기 끝 3.5~5주 뒤(다음 10/31 예정)', N'data.go.kr 15083033 — 새 파일 있을 때만 받음(없으면 건너뜀)', 'skip', 0),
 (N'학구도', N'통학구역', 'cl-hakgudo-par', 'quarterly 3,4,9,10 1 05:00', N'반기 · 3월 · 9월 배포(실제 1~5주 늦음)', N'data.go.kr 15159265 · 15159264 · 15159263 · 15159266', 'skip', 0),
 (N'학교 위치', N'학교', 'cl-school-par', 'monthly 10 05:00', N'수시(최근 2026-10-06)', N'data.go.kr 15021148', 'once', 0),
 (N'학교알리미', N'학교알리미', 'cl-schoolinfo-par', 'quarterly 5,6,10,12 10 05:00', N'정시 공시 4월 · 5월 · 9월 · 11월', N'학교알리미 공시 일정(경남교육청 안내)', 'once', 0),
 (N'유치원알리미', N'유치원', 'cl-kinder-par', 'quarterly 5,11 10 05:30', N'정시 공시 4월 · 10월', N'유치원알리미 공시 일정', 'once', 0),
 (N'어린이집 · 학원 · 병원 · 약국', N'병원', 'cl-life-par', 'weekly wed 04:00', N'실시간 · 수시', N'data.go.kr 15101155 · 15096277 · 15001698 · 15001673 · 15154822', 'once', 0),
 (N'지하철역', N'지하철역', 'cl-subway-par', 'yearly 12-28 05:00', N'연간(다음 2026-12-20)', N'data.go.kr 15013205', 'once', 0),
 (N'버스정류장', N'버스정류장', 'cl-busstop-par', 'yearly 11-05 05:00', N'연간 · 연 1회 수집(다음 2026-10-30)', N'data.go.kr 15067528', 'once', 0),
 (N'행정동 경계', N'행정동경계', 'cl-adm-par', 'quarterly 2,8 10 05:00', N'반기(다음 2027-02-01)', N'data.go.kr 15129688 SGIS', 'once', 0),
 (N'정비구역(서울)', N'정비구역', 'cl-redev-par', 'quarterly 1,4,7,10 20 05:00', N'분기 · 기준일 뒤 약 3.5개월', N'서울 열린데이터 OA-22856', 'once', 0)
) AS s (이름, 자료, 작업, 주기, 출처주기, 근거, 못돎이면, 켜짐)
ON d.이름 = s.이름
WHEN MATCHED THEN UPDATE SET 자료 = s.자료, 작업 = s.작업, 주기 = s.주기, 출처주기 = s.출처주기, 근거 = s.근거, 못돎이면 = s.못돎이면, 켜짐 = s.켜짐
WHEN NOT MATCHED THEN INSERT (이름, 자료, 작업, 주기, 출처주기, 근거, 못돎이면, 켜짐) VALUES (s.이름, s.자료, s.작업, s.주기, s.출처주기, s.근거, s.못돎이면, s.켜짐);
UPDATE ops.collect_schedule SET 근거 = N'data.go.kr 15126468 외 RTMS · rt.molit.go.kr "실시간 취합 후 익일 공개 · 계약일 기준"' WHERE 이름 = N'실거래 최근 3개월';
UPDATE ops.collect_schedule SET 근거 = N'data.go.kr 15077871 StanReginCd(실시간) — 국토부 파일 15063424 은 연간이라 늦다(구지읍 없음)' WHERE 이름 = N'법정동코드';
SELECT 켜짐, n = COUNT(*) FROM ops.collect_schedule GROUP BY 켜짐;
