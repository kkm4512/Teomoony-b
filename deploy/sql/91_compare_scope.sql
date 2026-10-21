SET NOCOUNT ON;
USE Teomoony;
GO
/* ============================================================
   91_compare_scope : 적재 범위별 비교 (읽기 전용, 진단용)

   종로구 하나로 세운 가정이 다른 동네에서도 성립하는지 본다.
   아무것도 바꾸지 않는다.
   ============================================================ */

PRINT '=== 1. 단지 묶기 ===';
SELECT sgg = c.sigungu_cd,
       단지 = COUNT(*),
       동1개 = SUM(CASE WHEN c.dong_cnt = 1 THEN 1 ELSE 0 END),
       동1개비율 = CAST(100.0 * SUM(CASE WHEN c.dong_cnt = 1 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,1)),
       총괄표제부 = SUM(CASE WHEN c.has_recap = 1 THEN 1 ELSE 0 END),
       평균동 = CAST(AVG(CAST(c.dong_cnt AS FLOAT)) AS DECIMAL(6,2)),
       최대동 = MAX(c.dong_cnt),
       좌표확보 = SUM(CASE WHEN c.centroid_lat IS NOT NULL THEN 1 ELSE 0 END)
FROM gold.complex c
GROUP BY c.sigungu_cd ORDER BY c.sigungu_cd;

PRINT '';
PRINT '=== 2. 실거래 매칭 (시군구별) ===';
SELECT sgg = r.sgg_cd,
       전체 = COUNT(*),
       마스킹 = SUM(CASE WHEN r.match_method = 'MASKED' THEN 1 ELSE 0 END),
       마스킹률 = CAST(100.0 * SUM(CASE WHEN r.match_method = 'MASKED' THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,1)),
       단지매칭 = SUM(CASE WHEN r.match_complex_id IS NOT NULL THEN 1 ELSE 0 END),
       마스킹제외매칭률 = CAST(100.0 * SUM(CASE WHEN r.match_complex_id IS NOT NULL THEN 1 ELSE 0 END)
                      / NULLIF(COUNT(*) - SUM(CASE WHEN r.match_method = 'MASKED' THEN 1 ELSE 0 END), 0) AS DECIMAL(5,1))
FROM silver.rtms_trade r
GROUP BY r.sgg_cd ORDER BY r.sgg_cd;

PRINT '';
PRINT '=== 3. 매칭 방법별 ===';
SELECT r.sgg_cd, r.match_method, 건수 = COUNT(*)
FROM silver.rtms_trade r
GROUP BY r.sgg_cd, r.match_method ORDER BY r.sgg_cd, COUNT(*) DESC;

PRINT '';
PRINT '=== 4. 평형 묶기 (FLOOR) 가 단지당 몇 개를 만드는가 ===';
WITH g AS (
    SELECT match_complex_id AS cid,
           COUNT(DISTINCT CAST(FLOOR(COALESCE(exclu_use_ar, total_floor_ar)) AS INT)) AS grp,
           COUNT(DISTINCT COALESCE(exclu_use_ar, total_floor_ar)) AS raw,
           COUNT(*) AS cnt
    FROM silver.rtms_trade
    WHERE match_complex_id IS NOT NULL AND is_rent = 0 AND is_canceled = 0
      AND COALESCE(exclu_use_ar, total_floor_ar) IS NOT NULL
    GROUP BY match_complex_id
)
SELECT sgg = c.sigungu_cd,
       거래있는단지 = COUNT(*),
       평균평형수 = CAST(AVG(CAST(g.grp AS FLOAT)) AS DECIMAL(5,2)),
       최대평형수 = MAX(g.grp),
       묶기전평균 = CAST(AVG(CAST(g.raw AS FLOAT)) AS DECIMAL(5,2)),
       묶어서줄인비율 = CAST(100.0 * (1 - SUM(CAST(g.grp AS FLOAT)) / SUM(CAST(g.raw AS FLOAT))) AS DECIMAL(5,1))
FROM g JOIN gold.complex c ON c.complex_id = g.cid
GROUP BY c.sigungu_cd ORDER BY c.sigungu_cd;

PRINT '';
PRINT '=== 5. 마커가 점으로 남는 단지 (거래 미매칭) ===';
SELECT sgg = c.sigungu_cd,
       단지 = COUNT(*),
       거래있음 = SUM(CASE WHEN x.cnt > 0 THEN 1 ELSE 0 END),
       점으로남음 = SUM(CASE WHEN ISNULL(x.cnt, 0) = 0 THEN 1 ELSE 0 END),
       점비율 = CAST(100.0 * SUM(CASE WHEN ISNULL(x.cnt, 0) = 0 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,1))
FROM gold.complex c
OUTER APPLY (SELECT COUNT(*) AS cnt FROM silver.rtms_trade r
              WHERE r.match_complex_id = c.complex_id AND r.is_rent = 0 AND r.is_canceled = 0) x
GROUP BY c.sigungu_cd ORDER BY c.sigungu_cd;
GO
