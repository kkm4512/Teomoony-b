/* 남은 일을 세어서 본다 (2026-10-19). 추측하지 않는다. */
SET NOCOUNT ON;

SELECT 축 = '학교',       건수 = COUNT(*) FROM silver.school WHERE is_current = 1
UNION ALL SELECT '지하철역',   COUNT(*) FROM silver.subway_station WHERE is_current = 1
UNION ALL SELECT '버스정류장', COUNT(*) FROM silver.bus_stop      WHERE is_current = 1
UNION ALL SELECT '버스노선(받은 수)', COUNT(DISTINCT route_id) FROM silver.bus_route_station
UNION ALL SELECT '학구도(초등)', COUNT(*) FROM silver.school_zone
UNION ALL SELECT '상권(분기)',  COUNT(*) FROM silver.semas_quarter
UNION ALL SELECT '상권(현재)',  COUNT(*) FROM silver.semas_store WHERE is_current = 1
UNION ALL SELECT '단지(활성)',  COUNT(*) FROM gold.complex WHERE is_active = 1
UNION ALL SELECT '실거래',      COUNT(*) FROM silver.rtms_trade;

/* 지역별로 어디가 비었나
   ★ EXISTS 를 집계 안에 넣지 않는다 - 2026-10-19 에 **다섯 번째로** 같은 실수를 했다.
     거래가 붙은 단지는 미리 DISTINCT 로 한 번 접어서 LEFT JOIN 한다. */
SELECT 지역 = CASE c.sigungu_cd
                WHEN '11110' THEN '종로' WHEN '11290' THEN '성북'
                WHEN '11380' THEN '은평' WHEN '11650' THEN '서초(양재)'
                WHEN '41171' THEN '안양만안' WHEN '41173' THEN '안양동안'
                ELSE c.sigungu_cd END,
       단지 = COUNT(*),
       거래붙은단지 = COUNT(DISTINCT t.complex_id)
  FROM gold.complex c
  LEFT JOIN (SELECT DISTINCT complex_id = match_complex_id
               FROM silver.rtms_trade WHERE match_complex_id IS NOT NULL) t
         ON t.complex_id = c.complex_id
 WHERE c.is_active = 1
 GROUP BY c.sigungu_cd ORDER BY c.sigungu_cd;
