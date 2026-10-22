/* ============================================================
   319_closed_site_locate : 폐쇄·말소 대장 자리 중 **지금 필지가 없어 지도에 못 찍던 것**에 자리를 준다 (2026-10-23 새벽)
   ★ 왜(실측): 폐쇄 묶음 32.9만 중 12.7만(서울 12.1만)이 좌표가 없다 — 그 필지가 합병·환지로 지금 지적도에 없다.
     그 자리의 옛 건물 실거래(서울 12.6만)는 상세(11-216 ④)를 만들어도 **열 길이 없었다**(지도 핀이 없다).
   ★ 두 길만 — 둘 다 원문 기록이고, 지어내지 않는다. 어느 길로 찍었는지 위치근거 칸에 남긴다.
       ① 토지이동이력의 마지막 줄이 'N번과 합병되어 말소' 이고 그 N 필지가 지금 있다 → N 필지 중심(옛 땅은 N 안에 들어갔다)
       ② 대장 도로명주소(괄호 앞) = 지금 건물 대장의 도로명주소 · 그 주소의 지금 단지가 하나 → 그 단지 중심
          ★ 자리만 쓴다 — '지금 그 자리 단지'(now_complex_id)로는 안 쓴다. 둔촌주공 '양재대로 1340' 은 지금 둔촌파출소 주소다(뒤를 이은 단지가 아니다).
   ★ 302 의 usp_build_closed_site 가 끝에 부른다(다시 만들면 다시 찍는다).
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
IF COL_LENGTH('gold.closed_site', '위치근거') IS NULL
    ALTER TABLE gold.closed_site ADD 위치근거 NVARCHAR(80) NULL;
GO
CREATE OR ALTER PROCEDURE gold.usp_closed_site_locate
    @sgg CHAR(5) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE gold.closed_site SET 위치근거 = N'필지 중심'
     WHERE lat IS NOT NULL AND 위치근거 IS NULL AND (@sgg IS NULL OR LEFT(pnu, 5) = @sgg);

    /* ① 합병되어 말소 → 그 필지 */
    IF OBJECT_ID('tempdb..#m') IS NOT NULL DROP TABLE #m;
    SELECT s.site_key, 대상 = LEFT(h.이동사유, CASE WHEN CHARINDEX(N'번과 합병되어 말소', h.이동사유) > 0 THEN CHARINDEX(N'번과 합병되어 말소', h.이동사유) - 1 ELSE 0 END), s.pnu
      INTO #m
      FROM gold.closed_site s
      CROSS APPLY (SELECT TOP 1 x.이동사유 FROM silver.land_move_hist x WHERE x.pnu = s.pnu ORDER BY x.이동일 DESC, x.이력순번 DESC) h
     WHERE s.lat IS NULL AND (@sgg IS NULL OR LEFT(s.pnu, 5) = @sgg) AND h.이동사유 LIKE N'%번과 합병되어 말소';
    DELETE FROM #m WHERE 대상 LIKE '%[^0-9-]%' OR LEN(대상) NOT BETWEEN 1 AND 9 OR 대상 LIKE '%-%-%';
    ALTER TABLE #m ADD 새 CHAR(19);
    UPDATE #m SET 새 = LEFT(pnu, 11) + RIGHT('0000' + CASE WHEN CHARINDEX('-', 대상) > 0 THEN LEFT(대상, CHARINDEX('-', 대상) - 1) ELSE 대상 END, 4)
                                + RIGHT('0000' + CASE WHEN CHARINDEX('-', 대상) > 0 THEN SUBSTRING(대상, CHARINDEX('-', 대상) + 1, 10) ELSE '0' END, 4);
    UPDATE s SET lat = p.centroid_lat, lng = p.centroid_lng,
                 위치근거 = LEFT(N'합병된 필지(' + m.대상 + N'번) 중심 — 토지이동이력', 80)
      FROM gold.closed_site s JOIN #m m ON m.site_key = s.site_key
      JOIN silver.cadastral_parcel p ON p.pnu = m.새 AND p.is_current = 1 AND p.centroid_lat IS NOT NULL
     WHERE s.lat IS NULL;

    /* ② 같은 도로명주소의 지금 건물 */
    IF OBJECT_ID('tempdb..#s') IS NOT NULL DROP TABLE #s;
    SELECT s.site_key, 주소 = CAST(LTRIM(RTRIM(LEFT(s.new_plat_plc, CHARINDEX(N' (', s.new_plat_plc + N' (') - 1))) AS NVARCHAR(200))
      INTO #s FROM gold.closed_site s
     WHERE s.lat IS NULL AND s.new_plat_plc LIKE N'%[0-9]%' AND (@sgg IS NULL OR LEFT(s.pnu, 5) = @sgg);
    IF EXISTS (SELECT 1 FROM #s)
    BEGIN
        IF OBJECT_ID('tempdb..#b') IS NOT NULL DROP TABLE #b;
        SELECT DISTINCT 주소 = CAST(LTRIM(RTRIM(LEFT(b.new_plat_plc, CHARINDEX(N' (', b.new_plat_plc + N' (') - 1))) AS NVARCHAR(200)), cb.complex_id
          INTO #b FROM silver.bld_title b JOIN gold.complex_bld cb ON cb.mgm_bldrgst_pk = b.mgm_bldrgst_pk
         WHERE b.is_current = 1 AND b.new_plat_plc LIKE N'%[0-9]%'
           AND (@sgg IS NULL OR b.new_plat_plc LIKE (SELECT TOP 1 LEFT(new_plat_plc, 8) FROM gold.closed_site WHERE LEFT(pnu, 5) = @sgg AND new_plat_plc IS NOT NULL) + N'%');
        CREATE INDEX ix ON #b (주소);
        UPDATE s SET lat = c.centroid_lat, lng = c.centroid_lng,
                     위치근거 = LEFT(N'같은 도로명주소(' + h.주소 + N')의 지금 건물 자리', 80)
          FROM gold.closed_site s
          JOIN (SELECT x.site_key, x.주소, cid = MIN(b.complex_id) FROM #s x JOIN #b b ON b.주소 = x.주소
                 GROUP BY x.site_key, x.주소 HAVING COUNT(DISTINCT b.complex_id) = 1) h ON h.site_key = s.site_key
          JOIN gold.complex c ON c.complex_id = h.cid AND c.centroid_lat IS NOT NULL
         WHERE s.lat IS NULL;
    END
    SELECT 위치근거 = LEFT(ISNULL(위치근거, N'(없음)'), 5), n = COUNT(*) FROM gold.closed_site
     WHERE @sgg IS NULL OR LEFT(pnu, 5) = @sgg GROUP BY LEFT(ISNULL(위치근거, N'(없음)'), 5);
END
GO
EXEC gold.usp_closed_site_locate;
