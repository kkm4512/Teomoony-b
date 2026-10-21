/* 297 : 청약홈 공고 중 '못 품' 이던 주소를 load_applyhome.py 의 새 조각(괄호 안 지번 · 도로명)으로 다시 푼 값 (2026-10-21 밤)
   ★ 적재기를 지금 돌릴 수 없어(작업 줄이 다 참) 같은 함수로 푼 결과만 넣는다. 다음 적재부터는 적재기가 같은 값을 쓴다.
   ★ lawd_cd 가 비어 있는 공고만 건드린다. 법정동·지번 찾기는 296 의 SQL(후보 1일 때만)이 한다. */
SET NOCOUNT ON;
UPDATE p SET 주소_시군구 = v.sgg, 주소_동 = v.emd, 주소_산 = v.san, 주소_본번 = v.bun, 주소_부번 = v.ji, 주소근거 = v.근거,
             주소_도로 = v.도로, 주소_건물본번 = v.본번, 주소_건물부번 = v.부번
  FROM silver.applyhome_pblanc p
  JOIN (VALUES
(N'서울특별시 노원구 노원로 495 (상계동 690)',N'노원구',N'상계동',N'0',N'690',N'0',N'괄호 안 지번',NULL,NULL,NULL),
(N'서울특별시 강남구 수서동, 자곡동 일원 수서역세권 공공주택지구내 A3블록',N'강남구',NULL,NULL,NULL,NULL,N'못 품',NULL,NULL,NULL),
(N'서울특별시 양천구 신목로2길 7-12 (신정동, 어반클라쎄 목동)',N'양천구',NULL,NULL,NULL,NULL,N'도로명만 — 대장 대조 대기',N'신목로2길',7,12),
(N'서울특별시 강서구 강서로 353 (내발산동)',N'강서구',NULL,NULL,NULL,NULL,N'도로명만 — 대장 대조 대기',N'강서로',353,NULL),
(N'서울특별시 강남구 수서동, 자곡동 일원 수서역세권 공공주택지구 내 A3블록',N'강남구',NULL,NULL,NULL,NULL,N'못 품',NULL,NULL,NULL),
(N'서울특별시 성동구 용답1길 7-18 (용답동), 성동구 용답동 121번지 일원',N'성동구',N'용답동',N'0',N'121',N'0',N'괄호 안 지번',NULL,NULL,NULL),
(N'서울특별시 용산구 한강로 2가 210-1번지 일원',N'용산구',N'한강로2가',N'0',N'210',N'1',N'법정동 그대로',NULL,NULL,NULL),
(N'서울특별시 강북구 도봉로 232 (미아동)',N'강북구',NULL,NULL,NULL,NULL,N'도로명만 — 대장 대조 대기',N'도봉로',232,NULL),
(N'서울특별시 강북구 도봉로 222 (미아동)',N'강북구',NULL,NULL,NULL,NULL,N'도로명만 — 대장 대조 대기',N'도봉로',222,NULL),
(N'서울특별시 구로구 오리로7길 4(오류동)',N'구로구',NULL,NULL,NULL,NULL,N'도로명만 — 대장 대조 대기',N'오리로7길',4,NULL),
(N'서울특별시 강북구 솔샘로 265일대(미아동 705-1일원)',N'강북구',N'미아동',N'0',N'705',N'1',N'괄호 안 지번',NULL,NULL,NULL),
(N'서울특별시 강북구 삼양로64길 8(미아동)',N'강북구',NULL,NULL,NULL,NULL,N'도로명만 — 대장 대조 대기',N'삼양로64길',8,NULL),
(N'서울특별시 성북구 안암동 132-17 일원',N'성북구',N'안암동',N'0',N'132',N'17',N'법정동 그대로',NULL,NULL,NULL),
(N'서울특별시 관악구 신림로 185(신림동, 신림 스카이 아파트)',N'관악구',NULL,NULL,NULL,NULL,N'도로명만 — 대장 대조 대기',N'신림로',185,NULL),
(N'서울특별시 종로구 종로66길 35 (숭인동)',N'종로구',NULL,NULL,NULL,NULL,N'도로명만 — 대장 대조 대기',N'종로66길',35,NULL),
(N'서울특별시 서초구 신반포로19길 10 (반포동 1-1)',N'서초구',N'반포동',N'0',N'1',N'1',N'괄호 안 지번',NULL,NULL,NULL),
(N'서울특별시 도봉구 노해로40길 23 (쌍문동)',N'도봉구',NULL,NULL,NULL,NULL,N'도로명만 — 대장 대조 대기',N'노해로40길',23,NULL),
(N'서울특별시 관악구 장군봉13길 32 (봉천동)',N'관악구',NULL,NULL,NULL,NULL,N'도로명만 — 대장 대조 대기',N'장군봉13길',32,NULL),
(N'서울특별시 강동구 강일동 고덕강일공공주택지구 5블럭',N'강동구',NULL,NULL,NULL,NULL,N'못 품',NULL,NULL,NULL),
(N'서울특별시 중랑구 양원역로 110 (망우동)',N'중랑구',NULL,NULL,NULL,NULL,N'도로명만 — 대장 대조 대기',N'양원역로',110,NULL),
(N'서울특별시 서초구 남부순환로 323길 41-3일원(서초동 1451-65)',N'서초구',N'서초동',N'0',N'1451',N'65',N'괄호 안 지번',NULL,NULL,NULL),
(N'서울특별시 은평구 수색로20가길 9 (수색동)',N'은평구',NULL,NULL,NULL,NULL,N'도로명만 — 대장 대조 대기',N'수색로20가길',9,NULL),
(N'서울특별시 서초구 반포대로9길 70 (서초동, 서초 비버리캐슬)',N'서초구',NULL,NULL,NULL,NULL,N'도로명만 — 대장 대조 대기',N'반포대로9길',70,NULL),
(N'서울특별시 노원구 덕릉로102길 5 (상계동)',N'노원구',NULL,NULL,NULL,NULL,N'도로명만 — 대장 대조 대기',N'덕릉로102길',5,NULL),
(N'서울특별시 구로구 고척로12길 16 (개봉동)',N'구로구',NULL,NULL,NULL,NULL,N'도로명만 — 대장 대조 대기',N'고척로12길',16,NULL),
(N'서울특별시 양천구 곰달래로11길 56 (신월동, 스위트드림아파트)',N'양천구',NULL,NULL,NULL,NULL,N'도로명만 — 대장 대조 대기',N'곰달래로11길',56,NULL),
(N'서울특별시 강서구 송정로 53 (공항동)',N'강서구',NULL,NULL,NULL,NULL,N'도로명만 — 대장 대조 대기',N'송정로',53,NULL),
(N'서울특별시 서초구 강남대로107길 14 (잠원동)',N'서초구',NULL,NULL,NULL,NULL,N'도로명만 — 대장 대조 대기',N'강남대로107길',14,NULL),
(N'서울특별시 강동구 아리수로93가길 248-17 (강일동)',N'강동구',NULL,NULL,NULL,NULL,N'도로명만 — 대장 대조 대기',N'아리수로93가길',248,17),
(N'서울특별시 강남구 개포로 621 (개포동)',N'강남구',NULL,NULL,NULL,NULL,N'도로명만 — 대장 대조 대기',N'개포로',621,NULL),
(N'서울특별시 서초구 양재대로2길 8 (우면동)',N'서초구',NULL,NULL,NULL,NULL,N'도로명만 — 대장 대조 대기',N'양재대로2길',8,NULL),
(N'서울특별시 강동구 고덕로 427 (강일동, 고덕리엔파크2단지아파트)',N'강동구',NULL,NULL,NULL,NULL,N'도로명만 — 대장 대조 대기',N'고덕로',427,NULL),
(N'경기도 안양시 만안구 능곡로36번길 19 (안양동, 신성안양미소지움)',N'안양시만안구',NULL,NULL,NULL,NULL,N'도로명만 — 대장 대조 대기',N'능곡로36번길',19,NULL),
(N'서울특별시 강서구 공항대로 533 (염창동)',N'강서구',NULL,NULL,NULL,NULL,N'도로명만 — 대장 대조 대기',N'공항대로',533,NULL),
(N'서울특별시 중랑구 망우동, 신내동 일원 서울양원 공공주택지구 내 S2블록',N'중랑구',NULL,NULL,NULL,NULL,N'못 품',NULL,NULL,NULL),
(N'서울특별시 강서구 공항대로 42길 11(내발산동 649-3)',N'강서구',N'내발산동',N'0',N'649',N'3',N'괄호 안 지번',NULL,NULL,NULL),
(N'서울특별시 동대문구 장한로28가길 17 (장안동, VT Style)',N'동대문구',NULL,NULL,NULL,NULL,N'도로명만 — 대장 대조 대기',N'장한로28가길',17,NULL),
(N'서울특별시 강북구 4.19로9길 18 (수유동)',N'강북구',NULL,NULL,NULL,NULL,N'도로명만 — 대장 대조 대기',N'4.19로9길',18,NULL),
(N'경기도 안양시 만안구 연현로 79 (석수동, 한양수자인아파트)',N'안양시만안구',NULL,NULL,NULL,NULL,N'도로명만 — 대장 대조 대기',N'연현로',79,NULL)
  ) v(adr, sgg, emd, san, bun, ji, 근거, 도로, 본번, 부번) ON v.adr = p.hssply_adres
 WHERE p.lawd_cd IS NULL;
SELECT 고친공고 = @@ROWCOUNT;
GO
EXEC gold.usp_applyhome_road_to_jibun;
SELECT 남은못찾음 = (SELECT COUNT(*) FROM silver.applyhome_pblanc WHERE lawd_cd IS NULL);
GO
EXEC gold.usp_refresh_applyhome_link;
GO
SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 근거 = 주소근거, n = COUNT(*), 법정동 = SUM(CASE WHEN lawd_cd IS NOT NULL THEN 1 ELSE 0 END), 지번 = SUM(CASE WHEN pnu IS NOT NULL THEN 1 ELSE 0 END)
  FROM silver.applyhome_pblanc GROUP BY 주소근거 ORDER BY 2 DESC;
SELECT j = (SELECT 공고 = p.house_nm, p.hssply_adres, p.주소근거, p.pnu, l.complex_id, c.complex_nm, l.kapt_code, k.kapt_name, l.거리m
  FROM silver.applyhome_pblanc p JOIN gold.applyhome_link l ON l.house_manage_no = p.house_manage_no AND l.pblanc_no = p.pblanc_no
  LEFT JOIN gold.complex c ON c.complex_id = l.complex_id LEFT JOIN silver.kapt_complex k ON k.kapt_code = l.kapt_code AND k.is_current = 1
 WHERE p.주소근거 <> N'법정동 그대로' FOR JSON PATH);
