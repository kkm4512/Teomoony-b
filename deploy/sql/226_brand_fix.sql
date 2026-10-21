/* ============================================================
   226_brand_fix : 브랜드를 **영문 표기도** 알아보게 한다 (2026-10-20)

   왜: 사용자가 'GS25계동' 의 브랜드가 비어 있는 것을 찾아냈다.
   상호가 한글 음차('지에스25')로 들어온다고만 보고 영문을 안 봤다.

   세어 보니 (224/225 probe, 서울+안양 편의점 2,557곳):
       GS25   음차 528 + 영문 223   <- 영문이 30%다. 가장 큰 구멍.
       CU     음차 693 + 영문  39
       세븐일레븐 390 + 영문   6
       이마트24   195 + 영문   1
     카페/빵집/햄버거/올리브영/다이소는 영문 표기가 **0건**이다 — 손대지 않는다.

   ★ CU 만 가둔다. 두 글자라 헛걸린다:
     편의점 밖에서 '%CU%' 는 7건이 걸리는데 **7건 전부 남의 가게**다
     (한칸cube · Custom_Car · CucharaLatina · curry-ya · itcustom · STONECUBE ·
      CU영어교습소). 그래서 CU 는 편의점/슈퍼마켓 안에서만 본다.
     그 안에서는 39건 전부 진짜 CU 였다(비지에프리테일CU명동역점 포함).
   ★ GS25 는 안 가둔다. 편의점 밖 4건이 **전부 진짜 GS25**(슈퍼마켓으로 분류된 점포)다.
   ★ 전각 숫자(GS２５고대개운점)는 이미 걸린다 — 이 DB 대조는 폭 구분을 안 한다.

   ★ 바뀌는 것은 brand 칸뿐이다. 행도, 다른 칸도 그대로다.
   ★ 이건 **읽는 방식을 고친 것**이지 없는 값을 지어낸 것이 아니다.
     상호에 GS25 라고 적혀 있으면 GS25 로 읽는다. 안 적혀 있으면 여전히 비워 둔다.
   ============================================================ */
USE Teomoony;
GO
IF OBJECT_ID('gold.v_complex_poi') IS NOT NULL DROP VIEW gold.v_complex_poi;
GO
CREATE VIEW gold.v_complex_poi
AS
SELECT c.complex_id,
       s.bizes_id, s.bizes_nm, s.brch_nm,
       s.inds_lcls_cd, s.inds_lcls_nm, s.inds_mcls_cd, s.inds_mcls_nm,
       s.inds_scls_nm, s.pnu, s.bld_mng_no, s.bld_nm, s.flr_no,
       /* ★ 새로 — 지도에 점을 찍으려면 좌표가 있어야 한다 */
       s.lat, s.lon,
       dist_m = s.geog.STDistance(geography::Point(c.centroid_lat, c.centroid_lng, 4326)),
       /* 이 단지 땅 위인가 — 거리와 **다른 축**이다 */
       on_site = CASE WHEN EXISTS (SELECT 1 FROM gold.complex_pnu cp
                                    WHERE cp.complex_id = c.complex_id AND cp.pnu = s.pnu)
                      THEN 1 ELSE 0 END,
       /* ★ 생활 항목 — 전에는 _q_poiLife 안에 있던 규칙을 그대로 옮겼다.
          학원은 한 덩어리로 묶으면 거짓말이 된다(2026-10-19): P1 전체를 '학원·교육' 으로
          세던 때는 요가/필라테스 학원과 직원 훈련기관·교육컨설팅까지 애 학원으로 세었다.
          소분류로 쪼개고 성인·직업 교육은 묶음에서 뺀다(소분류 막대에는 그대로 남는다). */
       life = CASE
           WHEN s.inds_scls_nm = N'편의점'   THEN N'편의점'
           WHEN s.inds_scls_nm = N'슈퍼마켓' THEN N'마트·슈퍼'
           WHEN s.inds_mcls_cd = 'I212'      THEN N'카페'
           WHEN s.inds_scls_nm = N'빵/도넛'  THEN N'빵집'
           WHEN s.inds_mcls_cd = 'I211'      THEN N'주점'
           WHEN s.inds_lcls_cd = 'I2'        THEN N'음식점'
           WHEN s.inds_scls_nm = N'약국'     THEN N'약국'
           WHEN s.inds_lcls_cd = 'Q1'        THEN N'병원·의원'
           WHEN s.inds_scls_nm = N'입시·교과학원' THEN N'입시·보습학원'
           WHEN s.inds_scls_nm = N'외국어학원'    THEN N'영어·외국어'
           WHEN s.inds_scls_nm IN (N'음악학원', N'미술학원', N'태권도/무술학원',
                                   N'기타 예술/스포츠 교육기관') THEN N'예체능학원'
           WHEN s.inds_scls_nm IN (N'컴퓨터 학원', N'전문자격/고시학원',
                                   N'레크리에이션 교육기관', N'그 외 기타 교육기관',
                                   N'사회교육시설', N'청소년 수련시설', N'운전학원')
                                                 THEN N'그 외 학원'
           /* 요가/필라테스는 '학원' 이라는 이름만 학원이다. 운동으로 보낸다. */
           WHEN s.inds_scls_nm = N'요가/필라테스 학원' THEN N'헬스·요가'
           WHEN s.inds_scls_nm = N'헬스장'   THEN N'헬스·요가'
           WHEN s.inds_scls_nm = N'미용실'   THEN N'미용실'
           WHEN s.inds_scls_nm = N'세탁소'   THEN N'세탁소'
       END,
       /* ★ 브랜드 — 전에는 _q_poiBrand 의 VALUES 목록이었다. 상호 **문자열 매칭**이다. */
       brand = CASE
           WHEN s.bizes_nm LIKE N'%씨유%'       THEN N'CU'
           /* ★ CU 는 편의점/슈퍼마켓 안에서만 — 밖에서는 남의 가게만 걸린다 */
           WHEN s.inds_scls_nm IN (N'편의점', N'슈퍼마켓')
                AND s.bizes_nm LIKE N'%CU%'     THEN N'CU'
           WHEN s.bizes_nm LIKE N'%지에스25%'   THEN N'GS25'
           WHEN s.bizes_nm LIKE N'%GS25%'       THEN N'GS25'
           WHEN s.bizes_nm LIKE N'%세븐일레븐%' THEN N'세븐일레븐'
           WHEN s.bizes_nm LIKE N'%7-ELEVEN%'
                OR s.bizes_nm LIKE N'%7ELEVEN%'
                OR s.bizes_nm LIKE N'%SEVEN ELEVEN%' THEN N'세븐일레븐'
           WHEN s.bizes_nm LIKE N'%이마트24%'   THEN N'이마트24'
           WHEN s.bizes_nm LIKE N'%EMART24%'    THEN N'이마트24'
           WHEN s.bizes_nm LIKE N'%미니스톱%'   THEN N'미니스톱'
           WHEN s.bizes_nm LIKE N'%MINISTOP%'   THEN N'미니스톱'
           WHEN s.bizes_nm LIKE N'%올리브영%'   THEN N'올리브영'
           WHEN s.bizes_nm LIKE N'%다이소%'     THEN N'다이소'
           WHEN s.bizes_nm LIKE N'%노브랜드%'   THEN N'노브랜드'
           WHEN s.bizes_nm LIKE N'%스타벅스%'   THEN N'스타벅스'
           WHEN s.bizes_nm LIKE N'%투썸%'       THEN N'투썸'
           WHEN s.bizes_nm LIKE N'%이디야%'     THEN N'이디야'
           WHEN s.bizes_nm LIKE N'%메가커피%'   THEN N'메가커피'
           WHEN s.bizes_nm LIKE N'%컴포즈%'     THEN N'컴포즈'
           WHEN s.bizes_nm LIKE N'%빽다방%'     THEN N'빽다방'
           WHEN s.bizes_nm LIKE N'%파리바게뜨%' THEN N'파리바게뜨'
           WHEN s.bizes_nm LIKE N'%뚜레쥬르%'   THEN N'뚜레쥬르'
           WHEN s.bizes_nm LIKE N'%맥도날드%'   THEN N'맥도날드'
           WHEN s.bizes_nm LIKE N'%버거킹%'     THEN N'버거킹'
           WHEN s.bizes_nm LIKE N'%롯데리아%'   THEN N'롯데리아'
       END
  FROM gold.complex c
  JOIN silver.semas_store s
    ON s.is_current = 1 AND s.geog IS NOT NULL
   AND s.geog.STDistance(geography::Point(c.centroid_lat, c.centroid_lng, 4326)) <= 1000
 WHERE c.is_active = 1 AND c.centroid_lat IS NOT NULL;
GO

PRINT '--- 확인: 편의점 브랜드가 얼마나 채워졌나 (고치기 전 1,850 / 2,557) ---';
SELECT 편의점 = COUNT(*),
       브랜드있음 = SUM(CASE WHEN brand IS NOT NULL THEN 1 ELSE 0 END),
       CU    = SUM(CASE WHEN brand = N'CU'    THEN 1 ELSE 0 END),
       GS25  = SUM(CASE WHEN brand = N'GS25'  THEN 1 ELSE 0 END),
       세븐  = SUM(CASE WHEN brand = N'세븐일레븐' THEN 1 ELSE 0 END),
       이마트24 = SUM(CASE WHEN brand = N'이마트24' THEN 1 ELSE 0 END)
  FROM (SELECT DISTINCT s.bizes_id, s.inds_scls_nm,
               brand = CASE
                 WHEN s.bizes_nm LIKE N'%씨유%' THEN N'CU'
                 WHEN s.inds_scls_nm IN (N'편의점', N'슈퍼마켓') AND s.bizes_nm LIKE N'%CU%' THEN N'CU'
                 WHEN s.bizes_nm LIKE N'%지에스25%' OR s.bizes_nm LIKE N'%GS25%' THEN N'GS25'
                 WHEN s.bizes_nm LIKE N'%세븐일레븐%' OR s.bizes_nm LIKE N'%7-ELEVEN%'
                   OR s.bizes_nm LIKE N'%7ELEVEN%' OR s.bizes_nm LIKE N'%SEVEN ELEVEN%' THEN N'세븐일레븐'
                 WHEN s.bizes_nm LIKE N'%이마트24%' OR s.bizes_nm LIKE N'%EMART24%' THEN N'이마트24'
                 WHEN s.bizes_nm LIKE N'%미니스톱%' OR s.bizes_nm LIKE N'%MINISTOP%' THEN N'미니스톱'
               END
          FROM silver.semas_store s
         WHERE s.is_current = 1 AND s.inds_scls_nm = N'편의점') q;
GO
PRINT '--- 확인: 40866 의 GS25계동 에 브랜드가 붙었나 ---';
SELECT TOP 3 bizes_nm, brand, 거리 = CAST(dist_m AS INT)
  FROM gold.v_complex_poi
 WHERE complex_id = 40866 AND bizes_nm LIKE N'%GS25%'
 ORDER BY dist_m;
GO
