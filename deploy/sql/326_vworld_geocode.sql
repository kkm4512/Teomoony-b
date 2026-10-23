/* ============================================================
   326_vworld_geocode : 좌표 없는 단지 — **대장 도로명주소 → VWorld 지오코더(공식) → 점** (2026-10-23 사장님 "1. ㄱㄱ")
   ★ 왜: 324(공식 주소의 지번 필지)로도 자리를 못 받은 단지 — 공식 지번이 지금 지적도에 없다(마곡 엠밸리 9단지 '마곡동 744' · 우디안 · 파크샤인).
     VWorld 지오코더(req/address getcoord type=ROAD)는 도로명주소 → 건물 점을 준다('공항대로 103' → 점 + '(마곡동,마곡 엠밸리 9단지)').
   ★ 규칙: 물은 주소(동 대장 도로명주소의 괄호 앞) = 지오코더가 돌려준 정제 주소의 괄호 앞 **글자 그대로** 일 때만 그 점. 자리만 준다(complex_pnu 는 안 건드림).
     324 의 필지 자리가 있으면 그쪽이 먼저(필지 > 점). 단지의 여러 동이 여러 점이면 그 점들을 감싸는 상자의 가운데.
   ★ 받기: VM etl/geocode_vm.py (DB 에 못 닿음) — 물을 말은 /api/_export?name=geo_ask.
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
IF OBJECT_ID('silver.vworld_geocode') IS NULL
CREATE TABLE silver.vworld_geocode (
    keyword   NVARCHAR(300) NOT NULL CONSTRAINT pk_vworld_geocode PRIMARY KEY,
    종류      VARCHAR(10)   NOT NULL,          -- ROAD
    status    VARCHAR(20)   NULL,              -- OK | NOT_FOUND | ERROR
    x         DECIMAL(12,8) NULL,
    y         DECIMAL(12,8) NULL,
    refined   NVARCHAR(400) NULL,              -- 정제 주소 원문
    받은때    DATETIME2(0)  NOT NULL CONSTRAINT df_vworld_geocode_t DEFAULT SYSDATETIME()
);
GO
/* 물을 말: 324 로도 자리가 없는 단지의 동 대장 도로명주소(괄호 앞) · 서울·안양 · 아직 안 물은 것 */
CREATE OR ALTER VIEW gold.v_geocode_ask_complex
AS
SELECT DISTINCT keyword = CAST(LTRIM(RTRIM(LEFT(b.new_plat_plc, CHARINDEX(N' (', b.new_plat_plc + N' (') - 1))) AS NVARCHAR(300))
  FROM gold.complex c
  JOIN gold.complex_bld cb ON cb.complex_id = c.complex_id
  JOIN silver.bld_title b ON b.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND b.is_current = 1
 WHERE c.is_active = 1 AND c.merged_into IS NULL AND c.centroid_lat IS NULL
   AND (c.sigungu_cd LIKE '11%' OR c.sigungu_cd IN ('41171', '41173'))
   AND b.new_plat_plc LIKE N'%[0-9]%'
   AND NOT EXISTS (SELECT 1 FROM gold.complex_pnu cp JOIN silver.cadastral_parcel q ON q.pnu = cp.pnu AND q.is_current = 1 WHERE cp.complex_id = c.complex_id);
GO
CREATE OR ALTER PROCEDURE gold.usp_complex_geo_juso
AS
BEGIN
    SET NOCOUNT ON;
    /* ① 324: 공식 주소의 지금 필지 */
    IF OBJECT_ID('tempdb..#h') IS NOT NULL DROP TABLE #h;
    SELECT DISTINCT c.complex_id, p.pnu, p.bbox_minx, p.bbox_miny, p.bbox_maxx, p.bbox_maxy, 주소 = e.keyword
      INTO #h
      FROM gold.complex c
      JOIN gold.complex_bld cb ON cb.complex_id = c.complex_id
      JOIN silver.bld_title b ON b.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND b.is_current = 1
      JOIN gold.v_juso_exact e ON e.keyword = CAST(LTRIM(RTRIM(LEFT(b.new_plat_plc, CHARINDEX(N' (', b.new_plat_plc + N' (') - 1))) AS NVARCHAR(300))
      JOIN silver.cadastral_parcel p ON p.pnu = e.pnu AND p.is_current = 1 AND p.bbox_minx IS NOT NULL
     WHERE c.is_active = 1 AND c.merged_into IS NULL AND b.new_plat_plc LIKE N'%[0-9]%'
       AND (c.centroid_lat IS NULL OR EXISTS (SELECT 1 FROM gold.complex_geo_alt a WHERE a.complex_id = c.complex_id))
       AND NOT EXISTS (SELECT 1 FROM gold.complex_pnu cp JOIN silver.cadastral_parcel q ON q.pnu = cp.pnu AND q.is_current = 1 WHERE cp.complex_id = c.complex_id)
       AND LEFT(e.pnu, 5) = c.sigungu_cd;
    /* ② 326: VWorld 지오코더 — 정제 주소(괄호 앞) = 물은 주소 */
    IF OBJECT_ID('tempdb..#v') IS NOT NULL DROP TABLE #v;
    SELECT DISTINCT c.complex_id, x = g.x, y = g.y, 주소 = g.keyword
      INTO #v
      FROM gold.complex c
      JOIN gold.complex_bld cb ON cb.complex_id = c.complex_id
      JOIN silver.bld_title b ON b.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND b.is_current = 1
      JOIN silver.vworld_geocode g ON g.keyword = CAST(LTRIM(RTRIM(LEFT(b.new_plat_plc, CHARINDEX(N' (', b.new_plat_plc + N' (') - 1))) AS NVARCHAR(300))
     WHERE g.status = 'OK' AND g.x IS NOT NULL
       AND LTRIM(RTRIM(LEFT(g.refined, CHARINDEX(N' (', g.refined + N' (') - 1))) = g.keyword
       AND c.is_active = 1 AND c.merged_into IS NULL
       AND (c.centroid_lat IS NULL OR EXISTS (SELECT 1 FROM gold.complex_geo_alt a WHERE a.complex_id = c.complex_id))
       AND NOT EXISTS (SELECT 1 FROM gold.complex_pnu cp JOIN silver.cadastral_parcel q ON q.pnu = cp.pnu AND q.is_current = 1 WHERE cp.complex_id = c.complex_id)
       AND NOT EXISTS (SELECT 1 FROM #h h WHERE h.complex_id = c.complex_id);
    BEGIN TRAN;
        DELETE FROM gold.complex_geo_alt;                     /* 파생 */
        INSERT INTO gold.complex_geo_alt (complex_id, lat, lng, 필지수, 근거)
        SELECT complex_id, CAST((MIN(bbox_miny) + MAX(bbox_maxy)) / 2 AS DECIMAL(10,7)), CAST((MIN(bbox_minx) + MAX(bbox_maxx)) / 2 AS DECIMAL(10,7)),
               COUNT(DISTINCT pnu), LEFT(N'대장 도로명주소 → 행정안전부 주소의 공식 지번 필지 (' + MIN(주소) + CASE WHEN COUNT(DISTINCT 주소) > 1 THEN N' 외' ELSE N'' END + N')', 200)
          FROM #h GROUP BY complex_id;
        INSERT INTO gold.complex_geo_alt (complex_id, lat, lng, 필지수, 근거)
        SELECT complex_id, CAST((MIN(y) + MAX(y)) / 2 AS DECIMAL(10,7)), CAST((MIN(x) + MAX(x)) / 2 AS DECIMAL(10,7)),
               0, LEFT(N'대장 도로명주소 → VWorld 지오코더 건물 점 (' + MIN(주소) + CASE WHEN COUNT(DISTINCT 주소) > 1 THEN N' 외' ELSE N'' END + N')', 200)
          FROM #v GROUP BY complex_id;
        UPDATE c SET c.centroid_lat = a.lat, c.centroid_lng = a.lng,
                     c.bbox_minx = g.minx, c.bbox_miny = g.miny, c.bbox_maxx = g.maxx, c.bbox_maxy = g.maxy, c.updated_at = SYSDATETIME()
          FROM gold.complex c JOIN gold.complex_geo_alt a ON a.complex_id = c.complex_id
          JOIN (SELECT complex_id, minx = MIN(bbox_minx), miny = MIN(bbox_miny), maxx = MAX(bbox_maxx), maxy = MAX(bbox_maxy) FROM #h GROUP BY complex_id
                UNION ALL
                SELECT complex_id, MIN(x), MIN(y), MAX(x), MAX(y) FROM #v GROUP BY complex_id) g ON g.complex_id = c.complex_id;
    COMMIT;
    SELECT 자리줌 = (SELECT COUNT(*) FROM gold.complex_geo_alt);
END
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 물을말 = (SELECT COUNT(*) FROM gold.v_geocode_ask_complex), 받음 = (SELECT COUNT(*) FROM silver.vworld_geocode);
