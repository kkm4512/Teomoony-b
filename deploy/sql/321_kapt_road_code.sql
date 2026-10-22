/* ============================================================
   321_kapt_road_code : K-apt ↔ 단지 둘째 길을 **공식 코드로** — 317 의 '주소 글자 비교' 를 바꾼다 (2026-10-23 사장님 "법정동 도로명 모두 마스터와 같은 방식")
   ★ K-apt 는 도로명주소를 글자로만 준다 → 행정안전부 도로명주소 검색 API(320, silver.juso_result)에 물어 **도로명코드(12) · 건물본번 · 부번 · 지번(PNU)** 를 받는다.
     검색 API 는 비슷한 주소도 같이 준다('갈산로 15' → 4건, 다른 도로의 15번) → **물은 도로명 = 받은 도로명 · 물은 번호 = 받은 번호** 인 것만(정확히 하나일 때).
   ★ 둘째 길(이름은 안 본다 · 모두 맞아야):
       K-apt 의 공식 [도로명코드 + 건물본번 + 부번] = 그 단지 어느 동 대장의 [na_road_cd + na_main_bun + na_sub_bun]   (근거 '도로명코드')
         또는 K-apt 의 공식 지번(PNU) = 그 단지 필지                                                             (근거 '공식 지번')
       + 세대 5% 안 · 양쪽 하나씩 · 첫째 길 것은 안 건드림
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
IF COL_LENGTH('gold.kapt_road_link', '근거') IS NULL
    ALTER TABLE gold.kapt_road_link ADD 근거 NVARCHAR(40) NULL;
GO
/* 물은 말 → 정확히 맞는 공식 주소 하나 */
CREATE OR ALTER VIEW gold.v_juso_exact
AS
WITH q AS (
    SELECT l.keyword,
           번호 = RIGHT(l.keyword, CHARINDEX(' ', REVERSE(l.keyword) + ' ') - 1),
           앞 = LEFT(l.keyword, LEN(l.keyword) - CHARINDEX(' ', REVERSE(l.keyword) + ' '))
      FROM silver.juso_lookup l WHERE l.error_code = '0' AND l.total_count > 0
), q2 AS (
    SELECT keyword, 번호, 도로 = RIGHT(앞, CHARINDEX(' ', REVERSE(앞) + ' ') - 1),
           본 = TRY_CAST(CASE WHEN CHARINDEX('-', 번호) > 0 THEN LEFT(번호, CHARINDEX('-', 번호) - 1) ELSE 번호 END AS INT),
           부 = ISNULL(TRY_CAST(CASE WHEN CHARINDEX('-', 번호) > 0 THEN SUBSTRING(번호, CHARINDEX('-', 번호) + 1, 10) END AS INT), 0)
      FROM q
), m AS (
    SELECT q2.keyword, r.rn_mgt_sn, r.buld_mnnm, r.buld_slno, r.pnu, r.adm_cd
      FROM q2 JOIN silver.juso_result r ON r.keyword = q2.keyword
     WHERE r.rn = q2.도로 AND r.buld_mnnm = q2.본 AND ISNULL(r.buld_slno, 0) = q2.부 AND ISNULL(r.udrt_yn, '0') = '0'
)
SELECT keyword, rn_mgt_sn = MIN(rn_mgt_sn), buld_mnnm = MIN(buld_mnnm), buld_slno = MIN(buld_slno), pnu = MIN(pnu)
  FROM m GROUP BY keyword
HAVING COUNT(DISTINCT rn_mgt_sn) = 1 AND COUNT(DISTINCT pnu) = 1;
GO
CREATE OR ALTER PROCEDURE gold.usp_refresh_kapt_road_link
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @t DATETIME2 = SYSDATETIME();
    /* K-apt → 공식 코드 */
    IF OBJECT_ID('tempdb..#k') IS NOT NULL DROP TABLE #k;
    SELECT k.kapt_code, 세대 = COALESCE(NULLIF(k.hhld_cnt, 0), k.ho_cnt), e.rn_mgt_sn, e.buld_mnnm, e.buld_slno, e.pnu, 주소 = e.keyword
      INTO #k FROM silver.kapt_complex k
      JOIN gold.v_juso_exact e ON e.keyword = CAST(LTRIM(RTRIM(LEFT(k.doro_juso, PATINDEX('%[0-9] %', k.doro_juso + ' ')))) AS NVARCHAR(300))
     WHERE k.is_current = 1 AND COALESCE(NULLIF(k.hhld_cnt, 0), k.ho_cnt) > 0;
    /* 대장 동 → 도로명코드 · 건물번호 */
    IF OBJECT_ID('tempdb..#b') IS NOT NULL DROP TABLE #b;
    SELECT DISTINCT b.na_road_cd, bm = TRY_CAST(b.na_main_bun AS INT), bs = ISNULL(TRY_CAST(b.na_sub_bun AS INT), 0), cb.complex_id
      INTO #b FROM silver.bld_title b JOIN gold.complex_bld cb ON cb.mgm_bldrgst_pk = b.mgm_bldrgst_pk
     WHERE b.is_current = 1 AND b.na_road_cd IS NOT NULL AND ISNULL(b.na_ugrnd_cd, '0') = '0'
       AND (b.na_road_cd LIKE '11%' OR b.na_road_cd LIKE '4117%');
    CREATE INDEX ix ON #b (na_road_cd, bm, bs);
    BEGIN TRAN;
        DELETE FROM gold.kapt_road_link;                          /* 파생 — 이제 뷰는 첫째 길만 */
        SELECT complex_id, kapt_code INTO #t1 FROM gold.v_complex_kapt;
        SELECT k.kapt_code, c.complex_id, k.주소, k.세대, c.hhld_cnt_sum, 근거 = CAST(x.근거 AS NVARCHAR(40))
          INTO #m
          FROM #k k
          CROSS APPLY (SELECT b.complex_id, 근거 = N'도로명코드' FROM #b b WHERE b.na_road_cd = k.rn_mgt_sn AND b.bm = k.buld_mnnm AND b.bs = ISNULL(k.buld_slno, 0)
                       UNION SELECT cp.complex_id, N'공식 지번' FROM gold.complex_pnu cp WHERE cp.pnu = k.pnu) x
          JOIN gold.complex c ON c.complex_id = x.complex_id AND c.is_active = 1 AND c.merged_into IS NULL AND c.hhld_cnt_sum > 0
         WHERE ABS(c.hhld_cnt_sum - k.세대) <= 0.05 * k.세대
           AND NOT EXISTS (SELECT 1 FROM #t1 t WHERE t.kapt_code = k.kapt_code)
           AND NOT EXISTS (SELECT 1 FROM #t1 t WHERE t.complex_id = c.complex_id);
        INSERT INTO gold.kapt_road_link (kapt_code, complex_id, 주소, kapt_세대, 대장_세대, 근거)
        SELECT m.kapt_code, m.complex_id, MIN(m.주소), MIN(m.세대), MIN(m.hhld_cnt_sum),
               근거 = CASE WHEN COUNT(DISTINCT m.근거) > 1 THEN N'도로명코드 + 공식 지번' ELSE MIN(m.근거) END
          FROM #m m
         WHERE 1 = (SELECT COUNT(DISTINCT m2.complex_id) FROM #m m2 WHERE m2.kapt_code = m.kapt_code)
           AND 1 = (SELECT COUNT(DISTINCT m3.kapt_code)  FROM #m m3 WHERE m3.complex_id = m.complex_id)
         GROUP BY m.kapt_code, m.complex_id;
    COMMIT;
    SELECT 둘째길 = (SELECT COUNT(*) FROM gold.kapt_road_link), 초 = DATEDIFF(SECOND, @t, SYSDATETIME());
END
GO
SELECT 정확 = (SELECT COUNT(*) FROM gold.v_juso_exact), 물음 = (SELECT COUNT(*) FROM silver.juso_lookup);
GO
