/* 165. 실거래 등기일자가 얼마나 차 있나 (2026-10-19) — 읽기 전용 */
SET NOCOUNT ON;
PRINT '--- A. 매매 건 중 등기일자 보유 ---';
SELECT 매매 = COUNT(*),
       등기일자있음 = SUM(CASE WHEN NULLIF(LTRIM(rgst_date),'') IS NOT NULL THEN 1 ELSE 0 END),
       비율 = CAST(100.0*SUM(CASE WHEN NULLIF(LTRIM(rgst_date),'') IS NOT NULL THEN 1 ELSE 0 END)
                   / NULLIF(COUNT(*),0) AS DECIMAL(5,1))
  FROM silver.rtms_trade WHERE is_rent = 0;

PRINT '';
PRINT '--- B. 연도별 (등기일자는 최근부터 공개됐을 것이다) ---';
SELECT 연도 = deal_year, 매매 = COUNT(*),
       등기일자있음 = SUM(CASE WHEN NULLIF(LTRIM(rgst_date),'') IS NOT NULL THEN 1 ELSE 0 END),
       비율 = CAST(100.0*SUM(CASE WHEN NULLIF(LTRIM(rgst_date),'') IS NOT NULL THEN 1 ELSE 0 END)
                   / NULLIF(COUNT(*),0) AS DECIMAL(5,1))
  FROM silver.rtms_trade WHERE is_rent = 0 AND deal_year >= 2020
 GROUP BY deal_year ORDER BY deal_year DESC;

PRINT '';
PRINT '--- C. 값의 생김새 (형식을 모르고 쓰면 안 된다) ---';
SELECT TOP 10 rgst_date, 건수 = COUNT(*), 길이 = MAX(LEN(rgst_date))
  FROM silver.rtms_trade WHERE NULLIF(LTRIM(rgst_date),'') IS NOT NULL
 GROUP BY rgst_date ORDER BY COUNT(*) DESC;

PRINT '';
PRINT '--- D. 계약 -> 등기 지연 (일) ---';
WITH t AS (
  SELECT deal_ymd,
         r = CASE WHEN LEN(LTRIM(rgst_date)) = 8 AND ISNUMERIC(LTRIM(rgst_date)) = 1
                  THEN LTRIM(rgst_date) ELSE NULL END
    FROM silver.rtms_trade
   WHERE is_rent = 0 AND is_canceled = 0
     AND NULLIF(LTRIM(rgst_date),'') IS NOT NULL AND deal_ymd IS NOT NULL
), d AS (
  SELECT delay = DATEDIFF(DAY, CONVERT(DATE, deal_ymd, 112), CONVERT(DATE, r, 112))
    FROM t WHERE r IS NOT NULL
)
SELECT 건수 = COUNT(*), 평균일 = CAST(AVG(CAST(delay AS FLOAT)) AS DECIMAL(8,1)),
       최소 = MIN(delay), 최대 = MAX(delay),
       [30일이내] = SUM(CASE WHEN delay <= 30 THEN 1 ELSE 0 END),
       [31_60]   = SUM(CASE WHEN delay BETWEEN 31 AND 60 THEN 1 ELSE 0 END),
       [61_90]   = SUM(CASE WHEN delay BETWEEN 61 AND 90 THEN 1 ELSE 0 END),
       [91_180]  = SUM(CASE WHEN delay BETWEEN 91 AND 180 THEN 1 ELSE 0 END),
       [180초과] = SUM(CASE WHEN delay > 180 THEN 1 ELSE 0 END),
       [음수]    = SUM(CASE WHEN delay < 0 THEN 1 ELSE 0 END)
  FROM d;
