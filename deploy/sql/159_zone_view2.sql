/* 159. v_complex_zone 에서 대분류 폴리곤을 걷어낸다 (2026-10-19)

   ★ 무엇을 걷어내나
     uname 이 빈 폴리곤 7개. 측정 결과(158) —
       · 면적이 **자치구 전체와 일치**한다 (성북 24.66km² vs 실제 24.57)
       · 그 구의 세분 용도지역이 **100% 그 안에 들어간다** (덮임비율 전부 100.0)
     즉 세분의 **상위집합**이다. 용도지역 대분류(도시지역)로 **추정**한다 —
     ★ 이름이 비어 있어 원본으로는 확인할 수 없다. 추정이라고 적어 둔다.

   ★ 왜 뷰에서만 빼나
     silver 에는 **그대로 둔다.** 원본이 보낸 것을 지우지 않는다.
     'v_complex_zone' 은 "이 단지의 용도지역" 을 말하는 자리인데, 대분류는
     세분과 중복이라 더할 말이 없고, 넣으면 **모든 단지에 뜻 없는 칸**이
     하나씩 생긴다(래미안 장위 퍼스트하이가 NULL 50% 로 나왔다).

   ★ 조용히 빼지 않는다
     나중에 "왜 안 나오지" 가 되지 않도록 여기 적는다. 대분류를 보려면
     silver.land_use_zone 을 직접 보면 된다.

   ★ 대분류는 일부 구에만 있다 — 은평구 349구역에는 빈값이 0 이다.
     레이어가 고르지 않다. 그래서 '항상 있다' 고 가정하는 로직을 짜면 안 된다.
*/
IF OBJECT_ID('gold.v_complex_zone') IS NOT NULL DROP VIEW gold.v_complex_zone;
GO
CREATE VIEW gold.v_complex_zone
AS
SELECT cp.complex_id,
       z.zone_key, z.uname, z.dyear, z.dnum,
       xarea = p.geom.STIntersection(z.geom).STArea()
  FROM gold.complex_pnu cp
  JOIN silver.cadastral_parcel p
    ON p.pnu = cp.pnu AND p.is_current = 1 AND p.geom IS NOT NULL
  JOIN silver.land_use_zone z
    ON z.is_current = 1 AND z.geom IS NOT NULL
   AND LTRIM(ISNULL(z.uname, '')) <> ''        -- ★ 대분류 폴리곤 제외 (위 설명)
   AND z.bbox_minx <= p.bbox_maxx AND z.bbox_maxx >= p.bbox_minx
   AND z.bbox_miny <= p.bbox_maxy AND z.bbox_maxy >= p.bbox_miny
   AND z.geom.STIntersects(p.geom) = 1;
GO
PRINT '--- 다시 확인: 래미안 장위 퍼스트하이 ---';
SELECT 단지 = LEFT(c.complex_nm, 24), v.uname,
       비중 = CAST(100.0 * SUM(v.xarea) / SUM(SUM(v.xarea)) OVER () AS DECIMAL(5,1))
  FROM gold.v_complex_zone v
  JOIN gold.complex c ON c.complex_id = v.complex_id
 WHERE c.complex_nm LIKE N'%래미안%장위%퍼스트하이%'
 GROUP BY c.complex_nm, v.uname ORDER BY 비중 DESC;
