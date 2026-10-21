/* 206. 단지 ↔ 학원·교습소 (2026-10-20)
   ★ 반드시 complex_id 로 먼저 거른 뒤 쓴다. STDistance 가 든 뷰를 조건 없이
     조회하면 단지를 전부 센다(179 에 같은 경고가 있다). 뷰는 '재료' 지
     '결과' 가 아니다.

   ★ 1km 까지만 담는다 — 학교(2km)보다 좁게 잡는다. 서울 학원이 25,512곳이라
     대치동 같은 곳은 1km 안에만 수백 곳이 나온다. 2km 로 넓히면 '주변 학원'
     이 아니라 '구 전체 목록' 이 된다. 화면은 300m / 300~500m 로 또 쪼갠다
     (버스에서 배운 것 — 거리를 섞어 보여주면 아무것도 안 읽힌다).

   ★ 개원만 센다.
     단, 2026-10-20 실측에서는 서울 25,512건이 전부 '개원' 이어서 이 필터가
     지금은 아무것도 걸러내지 않는다. 그래도 남긴다 — 폐원이 나중에 섞여
     오면 조용히 화면에 들어오면 안 된다.

   ★ 좌표가 없는 행은 여기 안 나온다 — 그래서 v_academy_gap 을 같이 둔다.
     화면은 '좌표를 못 붙인 N 곳' 을 반드시 같이 적어야 한다. 안 적으면
     "우리 동네 학원이 왜 안 보이지" 가 조용한 거짓말이 된다.

   ★ 분야명은 실측 결과 12가지로 닫혀 있다 — 묶음은 207 에 짠다.
     이 뷰는 207 이 다시 만들어 덮어쓴다.
*/
IF OBJECT_ID('gold.v_complex_academy') IS NOT NULL DROP VIEW gold.v_complex_academy;
GO
CREATE VIEW gold.v_complex_academy AS
SELECT c.complex_id,
       a.academy_sk, a.aca_asnum, a.aca_nm, a.insti_sc_nm,
       a.realm_sc_nm, a.le_ord_nm, a.le_crse_list_nm, a.le_crse_nm,
       a.tofor_smtot, a.thcc_cntnt, a.thcc_othbc_yn,
       a.road_addr, a.road_addr_dtl, a.tel_no, a.lat, a.lon,
       dist_m = a.geog.STDistance(geography::Point(c.centroid_lat, c.centroid_lng, 4326))
  FROM gold.complex c
  JOIN silver.academy a
    ON a.is_current = 1 AND a.geog IS NOT NULL AND a.reg_sttus_nm = N'개원'
   AND a.geog.STDistance(geography::Point(c.centroid_lat, c.centroid_lng, 4326)) <= 1000
 WHERE c.is_active = 1 AND c.centroid_lat IS NOT NULL;
GO
PRINT '206 완료 - gold.v_complex_academy';
GO

/* ★ 구멍을 드러내는 뷰 — 좌표를 못 붙인 것이 몇 곳인지 숨기지 않는다 */
IF OBJECT_ID('gold.v_academy_gap') IS NOT NULL DROP VIEW gold.v_academy_gap;
GO
CREATE VIEW gold.v_academy_gap AS
SELECT 교육청    = office_cd,
       행정구역  = admst_zone_nm,
       전체      = COUNT(*),
       개원      = SUM(CASE WHEN reg_sttus_nm = N'개원' THEN 1 ELSE 0 END),
       좌표있음  = SUM(CASE WHEN geocode_status = 'OK'        THEN 1 ELSE 0 END),
       주소못찾음 = SUM(CASE WHEN geocode_status = 'NOT_FOUND' THEN 1 ELSE 0 END),
       /* ★ 지오코더가 **다른 주소**를 돌려준 것. 좌표를 넣지 않았다 —
          엉뚱한 곳에 찍힌 점은 아무도 못 알아채기 때문이다. */
       다른주소  = SUM(CASE WHEN geocode_status = 'MISMATCH'  THEN 1 ELSE 0 END),
       범위밖    = SUM(CASE WHEN geocode_status = 'RANGE'     THEN 1 ELSE 0 END),
       지오코딩실패 = SUM(CASE WHEN geocode_status LIKE 'FAIL%' THEN 1 ELSE 0 END),
       아직      = SUM(CASE WHEN geocode_status IS NULL        THEN 1 ELSE 0 END)
  FROM silver.academy
 WHERE is_current = 1
 GROUP BY office_cd, admst_zone_nm;
GO
PRINT '206 완료 - gold.v_academy_gap';
