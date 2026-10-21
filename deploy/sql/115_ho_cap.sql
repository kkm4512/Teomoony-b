/* ============================================================
   115_ho_cap : 호 목록 TOP 4000 이 어디서 잘리나 (읽기 전용)  2026-10-18

   화면이 **잘렸다는 사실을 모른다.** 고치는 법을 고르기 전에 규모를 잰다.
     - 4000 을 넘는 단지가 몇이고 최대가 얼마인가  -> 상한만 올리면 되는가
     - 한 동의 최대 호수는 얼마인가 -> '선택한 동만 받기' 로 바꾸면 충분한가
   둘 중 어느 쪽이 맞는지는 숫자가 정한다.
   ============================================================ */
USE Teomoony;
GO
SET NOCOUNT ON;
GO

PRINT '--- 1. 단지별 호수 분포 ---';
WITH c AS (SELECT complex_id, n = COUNT(*) FROM gold.v_complex_ho GROUP BY complex_id)
SELECT 구간 = CASE WHEN n > 8000 THEN N'8000+'
                   WHEN n > 4000 THEN N'4001~8000'
                   WHEN n > 2000 THEN N'2001~4000'
                   WHEN n > 1000 THEN N'1001~2000'
                   ELSE N'~1000' END,
       단지수 = COUNT(*)
  FROM c
 GROUP BY CASE WHEN n > 8000 THEN N'8000+'
               WHEN n > 4000 THEN N'4001~8000'
               WHEN n > 2000 THEN N'2001~4000'
               WHEN n > 1000 THEN N'1001~2000'
               ELSE N'~1000' END
 ORDER BY 1;
GO

PRINT '--- 2. 4000 을 넘는 단지 (잘리고 있는 것들) ---';
SELECT TOP 20 h.complex_id, 단지 = MAX(c.complex_nm), 호수 = COUNT(*),
       동수 = COUNT(DISTINCT h.동PK)
  FROM gold.v_complex_ho h
  LEFT JOIN gold.complex c ON c.complex_id = h.complex_id
 GROUP BY h.complex_id
HAVING COUNT(*) > 4000
 ORDER BY COUNT(*) DESC;
GO

PRINT '--- 3. ★ 한 동의 최대 호수 — 동 단위로 받으면 얼마면 되나 ---';
WITH d AS (SELECT complex_id, 동PK, n = COUNT(*) FROM gold.v_complex_ho GROUP BY complex_id, 동PK)
SELECT 최대 = MAX(n), 평균 = AVG(n * 1.0), 동수 = COUNT(*),
       [500초과] = SUM(CASE WHEN n > 500 THEN 1 ELSE 0 END),
       [1000초과] = SUM(CASE WHEN n > 1000 THEN 1 ELSE 0 END)
  FROM d;
GO

PRINT '--- 4. 전체 규모 ---';
SELECT 호전체 = COUNT(*), 단지수 = COUNT(DISTINCT complex_id) FROM gold.v_complex_ho;
GO
