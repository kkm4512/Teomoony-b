/* 405 (2026-11-01 사장님 "너 제안대로 ㄱㄱ") — 경계가 똑같은 정비구역 기록 묶음.
   서울시 원본(OA-22712)은 같은 땅을 사업 종류별로 따로 올린다(촉진구역 + 재개발 · 신속통합기획 + 재건축 · 미리내집 차수 …) — 211쌍.
   ★ 묶는 근거 = 경계 원문(geojson)이 글자 하나 다르지 않을 때뿐(상자 4칸이 같고 · geojson 이 같다). 이름은 안 본다.
   ★ 대표(지도 색 · 이름 · 검색 한 줄 · 누르면 여는 기록): 실제 사업 기록(재개발 · 재건축 · 소규모 정비 · 주거환경개선) → 촉진구역 → 신속통합기획 → 그 밖, 같으면 번호순.
     (화면 쪽 src/redev_groups.js 기록순위 와 같은 규칙 — 겹쳐보기는 이 뷰의 '대표' 칸을 그대로 쓴다)
   ★ 기록말 = 묶음의 모든 기록 '분류 · 추진단계' (대표 먼저) — 단계가 서로 달라도 고르지 않고 다 적는다. */
CREATE OR ALTER VIEW gold.v_redev_same AS
WITH z AS (
  SELECT present_sn, zone_nm, biz_nm, propel_nm, bbox_minx, bbox_miny, bbox_maxx, bbox_maxy, geojson,
         순위 = CASE WHEN biz_nm LIKE N'재개발%' OR biz_nm LIKE N'재건축%' OR biz_nm LIKE N'%가로주택%' OR biz_nm LIKE N'%소규모%'
                          OR biz_nm LIKE N'%자율주택%' OR biz_nm LIKE N'주거환경개선%' THEN 0
                     WHEN biz_nm = N'재정비촉진구역' THEN 1 WHEN biz_nm = N'신속통합기획' THEN 2 ELSE 3 END
    FROM silver.redev_zone WHERE is_current = 1),
g AS (
  SELECT a.present_sn,
         same_key = (SELECT MIN(b.present_sn) FROM z b
                      WHERE b.bbox_minx = a.bbox_minx AND b.bbox_miny = a.bbox_miny AND b.bbox_maxx = a.bbox_maxx AND b.bbox_maxy = a.bbox_maxy
                        AND b.geojson = a.geojson),
         a.순위, a.biz_nm, a.propel_nm, a.zone_nm
    FROM z a WHERE a.geojson IS NOT NULL)
SELECT g.present_sn, same_key = ISNULL(g.same_key, g.present_sn),
       묶음수 = COUNT(*) OVER (PARTITION BY ISNULL(g.same_key, g.present_sn)),
       대표 = CASE WHEN ROW_NUMBER() OVER (PARTITION BY ISNULL(g.same_key, g.present_sn) ORDER BY g.순위, g.present_sn) = 1 THEN 1 ELSE 0 END,
       기록말 = CASE WHEN COUNT(*) OVER (PARTITION BY ISNULL(g.same_key, g.present_sn)) > 1 THEN
                 (SELECT STRING_AGG(CONCAT(y.biz_nm, N' · ', ISNULL(y.propel_nm, N'단계 모름')), N' / ') WITHIN GROUP (ORDER BY y.순위, y.present_sn)
                    FROM g y WHERE y.same_key = g.same_key) END
  FROM g;
GO
SELECT 묶음 = COUNT(DISTINCT same_key), 기록 = COUNT(*), 대표 = SUM(대표), 겹친묶음 = COUNT(DISTINCT CASE WHEN 묶음수 > 1 THEN same_key END)
  FROM gold.v_redev_same;
SELECT * FROM gold.v_redev_same WHERE present_sn IN ('11000UQ120PS202407010702', '11000UQ120PS202411014477');
GO
