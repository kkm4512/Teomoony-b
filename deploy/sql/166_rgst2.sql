/* 166. 등기일자 제대로 재기 (2026-10-19) — 읽기 전용
   ★ 165 에서 형식을 YYYYMMDD 로 가정했다가 0건이 나왔다. 실제는 **YY.MM.DD** 다.
     형식을 먼저 찍어보지 않았으면 "등기일자가 쓸모없다" 로 결론 낼 뻔했다. */
SET NOCOUNT ON;
PRINT '--- A. 계약 -> 등기 지연 (일) ---';
WITH t AS (
  SELECT deal_ymd,
         r = CASE WHEN LTRIM(rgst_date) LIKE '[0-9][0-9].[0-9][0-9].[0-9][0-9]'
                  THEN '20' + REPLACE(LTRIM(rgst_date), '.', '') END
    FROM silver.rtms_trade
   WHERE is_rent = 0 AND is_canceled = 0
     AND NULLIF(LTRIM(rgst_date),'') IS NOT NULL AND deal_ymd IS NOT NULL
), d AS (
  SELECT delay = DATEDIFF(DAY, CONVERT(DATE, deal_ymd, 112), CONVERT(DATE, r, 112)) FROM t WHERE r IS NOT NULL
)
SELECT 건수 = COUNT(*), 평균일 = CAST(AVG(CAST(delay AS FLOAT)) AS DECIMAL(8,1)),
       중앙 = MAX(CASE WHEN p = 1 THEN delay END),
       최소 = MIN(delay), 최대 = MAX(delay),
       [30일내] = SUM(CASE WHEN delay <= 30 THEN 1 ELSE 0 END),
       [31_60] = SUM(CASE WHEN delay BETWEEN 31 AND 60 THEN 1 ELSE 0 END),
       [61_90] = SUM(CASE WHEN delay BETWEEN 61 AND 90 THEN 1 ELSE 0 END),
       [91_180] = SUM(CASE WHEN delay BETWEEN 91 AND 180 THEN 1 ELSE 0 END),
       [180초과] = SUM(CASE WHEN delay > 180 THEN 1 ELSE 0 END),
       [음수] = SUM(CASE WHEN delay < 0 THEN 1 ELSE 0 END)
  FROM (SELECT delay, p = CASE WHEN ROW_NUMBER() OVER (ORDER BY delay)
              = (COUNT(*) OVER () + 1) / 2 THEN 1 ELSE 0 END FROM d) x;

PRINT '';
PRINT '--- B. 등기일자가 *없는* 건은 최근 거래인가 (미등기 신호인가) ---';
SELECT 거래연월 = LEFT(deal_ymd, 6), 매매 = COUNT(*),
       등기없음 = SUM(CASE WHEN NULLIF(LTRIM(rgst_date),'') IS NULL THEN 1 ELSE 0 END),
       없음비율 = CAST(100.0*SUM(CASE WHEN NULLIF(LTRIM(rgst_date),'') IS NULL THEN 1 ELSE 0 END)
                      / NULLIF(COUNT(*),0) AS DECIMAL(5,1))
  FROM silver.rtms_trade
 WHERE is_rent = 0 AND is_canceled = 0 AND deal_ymd >= '20250101'
 GROUP BY LEFT(deal_ymd, 6) ORDER BY LEFT(deal_ymd, 6) DESC;

PRINT '';
PRINT '--- C. 등기일이 월말에 몰리나 (일자별) ---';
SELECT 일 = RIGHT(LTRIM(rgst_date), 2), 건수 = COUNT(*)
  FROM silver.rtms_trade
 WHERE is_rent = 0 AND LTRIM(rgst_date) LIKE '[0-9][0-9].[0-9][0-9].[0-9][0-9]'
 GROUP BY RIGHT(LTRIM(rgst_date), 2) ORDER BY COUNT(*) DESC;
