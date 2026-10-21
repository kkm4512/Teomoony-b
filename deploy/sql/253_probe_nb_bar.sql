/* v_newbuild_trade 가 building_ar 을 안 본다. 단지 상세(tradeStats/jeonse)는 11-105 에서
   COALESCE(exclu_use_ar, total_floor_ar, building_ar) 로 고쳤는데 이 뷰는 안 고쳤다.
   뷰 주석은 "단지 상세의 집계와 같은 규칙을 쓴다" 고 약속한다 — 11-105 와 같은 깨진 약속.
   ★ 고치기 전에 **몇 건·몇 단지에 영향이 있나** 를 전수로 센다. 0 이면 안 건드린다. */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 신축붙은거래 = COUNT(*),
       면적없음 = SUM(CASE WHEN COALESCE(r.exclu_use_ar, r.total_floor_ar) IS NULL THEN 1 ELSE 0 END),
       그중_building_ar있음 = SUM(CASE WHEN COALESCE(r.exclu_use_ar, r.total_floor_ar) IS NULL
                                       AND r.building_ar IS NOT NULL THEN 1 ELSE 0 END),
       해제전체 = SUM(CAST(r.is_canceled AS INT))
  FROM silver.rtms_trade r
 WHERE r.match_pnu IS NOT NULL AND r.match_complex_id IS NULL;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* 영향받는 신축이 몇 곳인가 (pnu 단위) */
SELECT 영향단지 = COUNT(DISTINCT r.match_pnu)
  FROM silver.rtms_trade r
 WHERE r.match_pnu IS NOT NULL AND r.match_complex_id IS NULL
   AND COALESCE(r.exclu_use_ar, r.total_floor_ar) IS NULL
   AND r.building_ar IS NOT NULL;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* 해제 때문에 마커≠상세 가 되는 신축이 몇 곳인가 */
SELECT 해제있는신축 = COUNT(*)
  FROM (SELECT r.match_pnu
          FROM silver.rtms_trade r
         WHERE r.match_pnu IS NOT NULL AND r.match_complex_id IS NULL
         GROUP BY r.match_pnu
        HAVING SUM(CAST(r.is_canceled AS INT)) > 0) x;
