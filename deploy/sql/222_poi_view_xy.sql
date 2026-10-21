/* ============================================================
   222_poi_view_xy : gold.v_complex_poi 에 좌표와 분류를 넣는다 (2026-10-20)

   ★ 왜: 사용자가 "주변 목록에 마우스를 올리면 지도에 그 자리를 점으로" 를 원한다.
     그러려면 **개별 점포의 좌표와 이름**이 필요한데 이 뷰에 좌표가 없었다.

   ★★ 더 중요한 이유 — **분류를 한 군데로 모은다.**
     '생활 항목'(편의점·카페·학원…)과 '브랜드'(CU·GS25…) 를 가르는 규칙이
     지금은 `_q_poiLife` 와 `_q_poiBrand` **쿼리 안에** 적혀 있다.
     점 목록을 만들려면 그 규칙을 **또 한 번** 적어야 하는데, 그러면
     개수를 세는 쪽과 점을 찍는 쪽이 **언젠가 갈라진다.**
     오늘 실거래에서 똑같은 일을 겪었다 — 마커는 24.3억을 띄우는데 상세는
     "실거래 없음" 이라고 했고, 원인은 두 질의가 서로 다른 WHERE 를 들고 있던 것이다
     (CONTEXT 11-81). **같은 사실을 두 곳에서 만들지 않는다.**
     그래서 life / brand 를 **뷰의 칸으로** 올린다. 세는 쪽도 찍는 쪽도 이 칸을 본다.

   ★ 행은 하나도 안 바뀐다. 칸만 는다 — 기존 질의는 그대로 돈다.
   ★ 브랜드 음차 주의(원래 주석 그대로 옮김): 상호가 한글 음차로 들어온다.
     GS25 -> '지에스25', CU -> '씨유'. 영문으로 찾으면 0건이다.
     편의점 기준 브랜드가 상호에 적힌 비율은 **73.8%** — "있다" 는 말할 수 있어도
     "없다" 는 말할 수 없다. 화면에 그렇게 적혀 있다.
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
           WHEN s.bizes_nm LIKE N'%지에스25%'   THEN N'GS25'
           WHEN s.bizes_nm LIKE N'%세븐일레븐%' THEN N'세븐일레븐'
           WHEN s.bizes_nm LIKE N'%이마트24%'   THEN N'이마트24'
           WHEN s.bizes_nm LIKE N'%미니스톱%'   THEN N'미니스톱'
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

PRINT '--- 확인: 칸이 늘었나 / 행은 그대로인가 ---';
SELECT TOP 3 complex_id, bizes_nm, lat, lon, life, brand,
       거리 = CAST(dist_m AS INT)
  FROM gold.v_complex_poi
 WHERE complex_id = 40866 AND life = N'편의점'
 ORDER BY dist_m;
GO
SELECT 편의점_1km = COUNT(*) FROM gold.v_complex_poi
 WHERE complex_id = 40866 AND life = N'편의점';
GO
