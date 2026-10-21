SET NOCOUNT ON;
USE Teomoony;
GO
/* 92_check_jangwi : 장위동만 떼어 본 매칭률 (읽기 전용)

   91 의 성북구 매칭률 14.6% 는 분모가 어긋난 값이다.
   실거래는 시군구 단위로만 받을 수 있어 성북구 39개 법정동이 전부 들어왔는데
   건축물대장은 장위동 하나만 적재했다. 나머지 38개 동 거래는 붙을 단지가 없다.
   장위동만 보면 종로구와 비슷해야 정상이다. */

PRINT '=== 장위동(umd_nm) 기준 ===';
SELECT 전체 = COUNT(*),
       마스킹 = SUM(CASE WHEN match_method = 'MASKED' THEN 1 ELSE 0 END),
       마스킹률 = CAST(100.0 * SUM(CASE WHEN match_method = 'MASKED' THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,1)),
       PNU조립 = SUM(CASE WHEN match_pnu IS NOT NULL THEN 1 ELSE 0 END),
       단지매칭 = SUM(CASE WHEN match_complex_id IS NOT NULL THEN 1 ELSE 0 END),
       마스킹제외매칭률 = CAST(100.0 * SUM(CASE WHEN match_complex_id IS NOT NULL THEN 1 ELSE 0 END)
                      / NULLIF(COUNT(*) - SUM(CASE WHEN match_method = 'MASKED' THEN 1 ELSE 0 END), 0) AS DECIMAL(5,1))
FROM silver.rtms_trade
WHERE sgg_cd = '11290' AND umd_nm = N'장위동';

PRINT '';
PRINT '=== 성북구 나머지 동은 왜 안 붙는가 (대장 없는 동) ===';
SELECT TOP 10 umd_nm,
       거래 = COUNT(*),
       PNU조립 = SUM(CASE WHEN match_pnu IS NOT NULL THEN 1 ELSE 0 END),
       단지매칭 = SUM(CASE WHEN match_complex_id IS NOT NULL THEN 1 ELSE 0 END)
FROM silver.rtms_trade
WHERE sgg_cd = '11290'
GROUP BY umd_nm ORDER BY COUNT(*) DESC;

PRINT '';
PRINT '=== 장위동 거래가 안 붙은 건의 사유 ===';
SELECT match_method, 건수 = COUNT(*),
       단지매칭 = SUM(CASE WHEN match_complex_id IS NOT NULL THEN 1 ELSE 0 END)
FROM silver.rtms_trade
WHERE sgg_cd = '11290' AND umd_nm = N'장위동'
GROUP BY match_method ORDER BY COUNT(*) DESC;
GO
