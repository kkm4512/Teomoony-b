/* 207. 학원 묶음 — 실측한 값으로만 짠다 (2026-10-20)
   ★ 서울(B10) 25,512건을 **전부 받아 센 뒤에** 짰다. 기억으로 닫힌 집합을
     지어내지 않았다. 세어 본 것:
       받은 25,512 / 기대 25,512 · 구멍 0
       자연키 겹침 0 · 학원지정번호 25,512개 = 행 수  ->  **1줄 = 1학원**
       도로명주소 없는 행 0건 · 서로 다른 도로명주소 12,366개
       등록상태 1가지: '개원' 25,512 (폐원·휴원은 이 API 로 오지 않는다)

   ★ 묶음은 **분야명으로만** 한다 — 12가지로 닫혀 있다:
       14,142 입시.검정 및 보습   6,540 예능(대)      1,323 국제화
          806 기예(대)             751 직업기술         692 기타(대)
          588 종합(대)             413 독서실           230 인문사회(대)
           25 정보                   1 특수교육(대)       1 (빈 값)
     아래 CASE 가 12가지를 **전부** 어딘가로 보낸다. 상권 P1 18개를 전부
     보냈던 것과 같은 방식이다.

   ★ 안 맞는 이름은 '기타' 로 넘기지 않고 grp 를 NULL 로 둔다 — 화면이
     '분류 못 함' 으로 드러낼 수 있게. (빈 값 1건이 이미 있다)

   ★ 교습과정명(109가지)은 **묶지 않고 그대로 보여준다.** '보습' '음악'
     '미술' '보습·논술' '실용외국어(유아/초·중·고)' '무용' '독서실' 처럼
     이미 사람 말이다. 109가지를 내 맘대로 묶으면 그게 거짓말이 된다.

   ★★ 교습과정목록명을 쉼표로 쪼개지 말 것 (2026-10-20 실측)
     '컴퓨터(정보처리,통신기기,인터넷,소프트웨어)' 가 네 조각이 되고
     '회60분)' '소믈리에)' '현대무용)' 같은 쓰레기가 3,803가지 나온다.
     괄호 안에 쉼표가 있고 수강료 시간표(주2회 60분)가 섞여 있다.

   ★ 나이로 가르지 않는다
     '기예' 를 '어른 학원' 으로 묶고 싶었는데 교습과정을 세어 보니 애견미용·
     꽃기예(어른) 와 **바둑 40 · 주산 10 · 속셈 10(아이)** 이 같이 있다.
     분야명만으로는 나이를 알 수 없다. 그래서 묶음에 나이를 적지 않고
     과정명을 그대로 보여준다 — 보는 사람이 판단한다.

   ※ 206 의 gold.v_complex_academy 를 여기서 다시 만든다(묶음 칸 추가).
*/
IF OBJECT_ID('gold.v_complex_academy') IS NOT NULL DROP VIEW gold.v_complex_academy;
GO
CREATE VIEW gold.v_complex_academy AS
SELECT c.complex_id,
       a.academy_sk, a.aca_asnum, a.aca_nm, a.insti_sc_nm,
       a.realm_sc_nm, a.le_ord_nm, a.le_crse_list_nm, a.le_crse_nm,
       a.tofor_smtot, a.thcc_cntnt, a.thcc_othbc_yn,
       a.road_addr, a.road_addr_dtl, a.tel_no, a.lat, a.lon,
       /* 화면 묶음 — 12가지를 전부 보낸다. 모르는 이름은 NULL */
       grp = CASE a.realm_sc_nm
               WHEN N'입시.검정 및 보습' THEN N'01 입시·보습'
               WHEN N'국제화'            THEN N'02 외국어'
               WHEN N'예능(대)'          THEN N'03 예능 (음악·미술·무용)'
               WHEN N'종합(대)'          THEN N'04 종합'
               WHEN N'인문사회(대)'      THEN N'05 인문사회'
               WHEN N'독서실'            THEN N'06 독서실'
               WHEN N'정보'              THEN N'07 컴퓨터·정보'
               WHEN N'기예(대)'          THEN N'08 기예 (바둑·주산·미용·꽃 등)'
               WHEN N'직업기술'          THEN N'09 직업기술'
               WHEN N'기타(대)'          THEN N'10 기타'
               WHEN N'특수교육(대)'      THEN N'11 특수교육'
               ELSE NULL                 /* ★ 조용히 '기타' 로 넘기지 않는다 */
             END,
       dist_m = a.geog.STDistance(geography::Point(c.centroid_lat, c.centroid_lng, 4326))
  FROM gold.complex c
  JOIN silver.academy a
    ON a.is_current = 1 AND a.geog IS NOT NULL AND a.reg_sttus_nm = N'개원'
   AND a.geog.STDistance(geography::Point(c.centroid_lat, c.centroid_lng, 4326)) <= 1000
 WHERE c.is_active = 1 AND c.centroid_lat IS NOT NULL;
GO
PRINT '207 완료 - gold.v_complex_academy (묶음 포함)';
GO

/* 검산 1 — 분야명 12가지가 전부 묶였나. '분류 못 함' 이 몇 건인가 */
SELECT grp = CASE realm_sc_nm
               WHEN N'입시.검정 및 보습' THEN N'01 입시·보습'
               WHEN N'국제화'            THEN N'02 외국어'
               WHEN N'예능(대)'          THEN N'03 예능 (음악·미술·무용)'
               WHEN N'종합(대)'          THEN N'04 종합'
               WHEN N'인문사회(대)'      THEN N'05 인문사회'
               WHEN N'독서실'            THEN N'06 독서실'
               WHEN N'정보'              THEN N'07 컴퓨터·정보'
               WHEN N'기예(대)'          THEN N'08 기예 (바둑·주산·미용·꽃 등)'
               WHEN N'직업기술'          THEN N'09 직업기술'
               WHEN N'기타(대)'          THEN N'10 기타'
               WHEN N'특수교육(대)'      THEN N'11 특수교육'
               ELSE NULL END,
       분야 = realm_sc_nm, 건수 = COUNT(*)
  FROM silver.academy WHERE is_current = 1
 GROUP BY realm_sc_nm ORDER BY COUNT(*) DESC;
GO
PRINT '  ↑ grp 가 NULL 인 줄이 곧 "분류 못 함" 이다. 분야명이 늘면 여기 나타난다.';
