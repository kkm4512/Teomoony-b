/* ============================================================
   239_kinder_xy : gold.v_complex_kinder 에 좌표를 넣는다 (2026-10-21)

   왜: 사용자가 "유치원에 마우스를 갖다대도 지도에 안 찍힌다" 고 했다.
     맞다 — 이 뷰에 **좌표가 없어서** 점을 찍을 수가 없었다.
     222(상권)·223(버스)에서 한 것과 같은 수선이다.
   ★ 행은 하나도 안 바뀐다. 칸만 는다 — 기존 질의는 그대로 돈다.
   ★ 반경 500m 는 **그대로 둔다.** 화면이 그렇게 적고 있다.
   ============================================================ */
USE Teomoony;
GO
IF OBJECT_ID('gold.v_complex_kinder') IS NOT NULL DROP VIEW gold.v_complex_kinder;
GO
CREATE VIEW gold.v_complex_kinder AS
SELECT c.complex_id,
       k.kinder_cd, k.kinder_nm, k.establish, k.addr, k.tel_no, k.oper_time,
       k.cap_cnt, k.pupil_cnt, k.class_cnt, k.pbnt_tmng,
       k.lat, lon = k.lng,          /* ★ 점 찍기용 */
       dist_m = c.geog.STDistance(k.geog)
  FROM (SELECT complex_id, geog = geography::Point(centroid_lat, centroid_lng, 4326)
          FROM gold.complex
         WHERE is_active = 1 AND centroid_lat IS NOT NULL AND centroid_lng IS NOT NULL) c
  JOIN silver.kindergarten k
    ON k.geog IS NOT NULL
   AND c.geog.STDistance(k.geog) <= 500;
GO
PRINT '--- 확인: 좌표가 붙었나 ---';
SELECT TOP 3 complex_id, kinder_nm, lat, lon, 거리 = CAST(dist_m AS INT)
  FROM gold.v_complex_kinder WHERE complex_id = 40866 ORDER BY dist_m;
GO
