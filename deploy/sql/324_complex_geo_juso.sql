/* ============================================================
   324_complex_geo_juso : 좌표 없는 대장 단지에 자리 — **대장 도로명주소 → 행정안전부 주소(정확히 같은 것) → 그 공식 지번 필지** (2026-10-23 사장님 "확실한건만 · ㄱㄱ")
   ★ 왜(실측, 서울): 좌표 없는 단지 18,062 — 전부 대장 지번이 지금 지적도에 없다(합필·택지·재개발). 그중 도로명주소가 있는 650(실거래 5,794건)만
     공식 주소로 지금 지번을 받을 수 있다. 지번만 있는 17,412(대부분 세대 없는 단독·근생)는 공식 자료에 자리가 없어 둔다.
   ★ 규칙: 동 대장 도로명주소(괄호 앞) → silver.juso_result 의 **정확히 같은 도로명 · 번호 · 지상 · 하나**(gold.v_juso_exact) → 그 PNU 의 **지금 필지** ·
           같은 시군구일 때만. 단지의 여러 동이 여러 필지를 가리키면 그 필지들을 다 감싸는 상자.
   ★ 자리만 준다 — complex_pnu(단지 필지)에는 넣지 않는다(실거래 필지 매칭이 바뀌지 않게). 근거는 gold.complex_geo_alt 에.
   ★ gold.usp_refresh_complex_geo(287) 를 여기서 다시 정의한다 — 287 본문 그대로 + 끝에 이 자리 주기(@complex_id 없을 때). 287 파일을 다시 돌리지 말 것(합치기 적용이 같이 돈다).
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
IF OBJECT_ID('gold.complex_geo_alt') IS NULL
CREATE TABLE gold.complex_geo_alt (
    complex_id  INT           NOT NULL CONSTRAINT pk_complex_geo_alt PRIMARY KEY,
    lat         DECIMAL(10,7) NOT NULL,
    lng         DECIMAL(10,7) NOT NULL,
    필지수      INT           NOT NULL,
    근거        NVARCHAR(200) NOT NULL,
    굳힌시각    DATETIME2(0)  NOT NULL CONSTRAINT df_complex_geo_alt_t DEFAULT SYSDATETIME()
);
GO
CREATE OR ALTER PROCEDURE gold.usp_complex_geo_juso
AS
BEGIN
    SET NOCOUNT ON;
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
    BEGIN TRAN;
        DELETE FROM gold.complex_geo_alt;                     /* 파생 */
        INSERT INTO gold.complex_geo_alt (complex_id, lat, lng, 필지수, 근거)
        SELECT complex_id, CAST((MIN(bbox_miny) + MAX(bbox_maxy)) / 2 AS DECIMAL(10,7)), CAST((MIN(bbox_minx) + MAX(bbox_maxx)) / 2 AS DECIMAL(10,7)),
               COUNT(DISTINCT pnu), LEFT(N'대장 도로명주소 → 행정안전부 주소의 공식 지번 필지 (' + MIN(주소) + CASE WHEN COUNT(DISTINCT 주소) > 1 THEN N' 외' ELSE N'' END + N')', 200)
          FROM #h GROUP BY complex_id;
        UPDATE c SET c.centroid_lat = a.lat, c.centroid_lng = a.lng,
                     c.bbox_minx = g.minx, c.bbox_miny = g.miny, c.bbox_maxx = g.maxx, c.bbox_maxy = g.maxy, c.updated_at = SYSDATETIME()
          FROM gold.complex c JOIN gold.complex_geo_alt a ON a.complex_id = c.complex_id
          JOIN (SELECT complex_id, minx = MIN(bbox_minx), miny = MIN(bbox_miny), maxx = MAX(bbox_maxx), maxy = MAX(bbox_maxy) FROM #h GROUP BY complex_id) g ON g.complex_id = c.complex_id;
    COMMIT;
    SELECT 자리줌 = (SELECT COUNT(*) FROM gold.complex_geo_alt);
END
GO
CREATE OR ALTER PROCEDURE gold.usp_refresh_complex_geo
    @complex_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    WITH g AS (
        SELECT cp.complex_id,
               MIN(p.bbox_minx) AS minx, MIN(p.bbox_miny) AS miny,
               MAX(p.bbox_maxx) AS maxx, MAX(p.bbox_maxy) AS maxy,
               AVG(p.jiga)      AS jiga_avg,
               COUNT(p.pnu)     AS hit
        FROM gold.complex_pnu cp
        JOIN silver.cadastral_parcel p ON p.pnu = cp.pnu AND p.is_current = 1
        WHERE (@complex_id IS NULL OR cp.complex_id = @complex_id)
        GROUP BY cp.complex_id
    )
    UPDATE c
       SET c.bbox_minx = g.minx, c.bbox_miny = g.miny,
           c.bbox_maxx = g.maxx, c.bbox_maxy = g.maxy,
           c.centroid_lng = CAST((g.minx + g.maxx) / 2 AS DECIMAL(10,7)),
           c.centroid_lat = CAST((g.miny + g.maxy) / 2 AS DECIMAL(10,7)),
           c.jiga_avg   = g.jiga_avg,
           c.parcel_hit = g.hit,
           c.updated_at = SYSDATETIME()
      FROM gold.complex c JOIN g ON g.complex_id = c.complex_id;
    /* 324: 필지로 자리를 못 받은 단지 — 공식 주소의 지금 필지로(결과 행은 버린다) */
    IF @complex_id IS NULL AND OBJECT_ID('gold.usp_complex_geo_juso') IS NOT NULL
    BEGIN
        CREATE TABLE #g324 (n INT);
        INSERT INTO #g324 EXEC gold.usp_complex_geo_juso;
    END
END
GO
EXEC gold.usp_complex_geo_juso;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 서울 = (SELECT COUNT(*) FROM gold.complex_geo_alt a JOIN gold.complex c ON c.complex_id = a.complex_id WHERE c.sigungu_cd LIKE '11%'),
       거래 = (SELECT COUNT(*) FROM silver.rtms_trade t JOIN gold.complex_geo_alt a ON a.complex_id = t.match_complex_id),
       예 = (SELECT TOP 15 c.complex_nm, c.hhld_cnt_sum, a.필지수, a.근거 FROM gold.complex_geo_alt a JOIN gold.complex c ON c.complex_id = a.complex_id ORDER BY c.hhld_cnt_sum DESC FOR JSON PATH);
