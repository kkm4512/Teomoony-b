/* 축 x 지역 적재 매트릭스 (2026-10-19)
   "완벽히 채워진 곳이 어디냐" 에 **세어서** 답하기 위한 것.
   ★ 집계 안에 서브쿼리를 넣지 않는다 - 오늘 다섯 번 당했다.
     붙었는지 여부는 미리 DISTINCT 로 접어서 LEFT JOIN 한다. */
SET NOCOUNT ON;

/* ---- 1) 단지에 붙는 축: 좌표 · 필지 · 건물 · 실거래 ---- */
WITH g AS (SELECT complex_id, sigungu_cd, centroid_lat FROM gold.complex WHERE is_active = 1),
     t AS (SELECT DISTINCT cid = match_complex_id FROM silver.rtms_trade
            WHERE match_complex_id IS NOT NULL),
     p AS (SELECT DISTINCT cp.complex_id FROM gold.complex_pnu cp
             JOIN silver.cadastral_parcel pa ON pa.pnu = cp.pnu AND pa.is_current = 1)
SELECT 지역 = CASE g.sigungu_cd
                WHEN '11110' THEN '종로' WHEN '11290' THEN '성북'
                WHEN '11380' THEN '은평' WHEN '11650' THEN '서초(양재)'
                WHEN '41171' THEN '안양만안' WHEN '41173' THEN '안양동안'
                ELSE g.sigungu_cd END,
       단지 = COUNT(*),
       좌표 = SUM(CASE WHEN g.centroid_lat IS NOT NULL THEN 1 ELSE 0 END),
       필지붙음 = COUNT(DISTINCT p.complex_id),
       거래붙음 = COUNT(DISTINCT t.cid)
  FROM g
  LEFT JOIN t ON t.cid = g.complex_id
  LEFT JOIN p ON p.complex_id = g.complex_id
 GROUP BY g.sigungu_cd ORDER BY g.sigungu_cd;

/* ---- 2) 지역이 sgg_cd 로 찍히는 축들 ---- */
SELECT 축 = '실거래', 지역 = sgg_cd, 건수 = COUNT(*) FROM silver.rtms_trade GROUP BY sgg_cd
UNION ALL SELECT '유치원', sgg_cd, COUNT(*) FROM silver.kindergarten GROUP BY sgg_cd
ORDER BY 축, 지역;
/* ★ 학교는 뺐다 - silver.school 에 sgg_cd 가 **없다**(2026-10-19).
   있다고 추측하고 썼다가 'Invalid column name' 으로 죽었다.
   컬럼은 추측하지 않는다. 학교는 전국으로 받았으니 총계만 아래에서 센다. */

/* ---- 3) 전국으로 받은 축 (지역을 안 가린다) ---- */
SELECT 축 = '지하철역',   건수 = COUNT(*) FROM silver.subway_station WHERE is_current = 1
UNION ALL SELECT '버스정류장', COUNT(*) FROM silver.bus_stop WHERE is_current = 1
UNION ALL SELECT '버스노선(받은 수)', COUNT(DISTINCT route_id) FROM silver.bus_route_station
UNION ALL SELECT '법정동코드', COUNT(*) FROM meta.lawd_code
UNION ALL SELECT '학구도(초등)', COUNT(*) FROM silver.school_zone
UNION ALL SELECT '유치원', COUNT(*) FROM silver.kindergarten
UNION ALL SELECT '상권(현재)', COUNT(*) FROM silver.semas_store WHERE is_current = 1
UNION ALL SELECT '상권(분기)', COUNT(*) FROM silver.semas_quarter
UNION ALL SELECT '필지', COUNT(*) FROM silver.cadastral_parcel WHERE is_current = 1
UNION ALL SELECT '건물외곽선', COUNT(*) FROM silver.building_footprint WHERE is_current = 1
UNION ALL SELECT '정비구역', COUNT(*) FROM silver.redev_zone;
