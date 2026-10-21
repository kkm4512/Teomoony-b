/* 164. 용도지역 이름 중 대분류로 못 묶는 게 있나 (2026-10-19) — 읽기 전용
   ★ 화면이 '분류 못 함' 으로 그리는 것이 실제로 무엇인지 세어 둔다.
     조용히 '기타' 로 넘기지 않기로 했으므로, 그 수를 알고 있어야 한다. */
SET NOCOUNT ON;
SELECT 대분류 = CASE WHEN uname LIKE N'%주거지역' THEN N'주거'
                     WHEN uname LIKE N'%상업지역' THEN N'상업'
                     WHEN uname LIKE N'%공업지역' THEN N'공업'
                     WHEN uname LIKE N'%녹지지역' THEN N'녹지'
                     ELSE N'(분류 못 함)' END,
       구역 = COUNT(*), 종류 = COUNT(DISTINCT uname)
  FROM silver.land_use_zone
 WHERE is_current = 1 AND LTRIM(ISNULL(uname,'')) <> ''
 GROUP BY CASE WHEN uname LIKE N'%주거지역' THEN N'주거'
               WHEN uname LIKE N'%상업지역' THEN N'상업'
               WHEN uname LIKE N'%공업지역' THEN N'공업'
               WHEN uname LIKE N'%녹지지역' THEN N'녹지'
               ELSE N'(분류 못 함)' END
 ORDER BY COUNT(*) DESC;
PRINT '';
PRINT '--- 분류 못 한 이름들 ---';
SELECT uname, 구역 = COUNT(*) FROM silver.land_use_zone
 WHERE is_current = 1 AND LTRIM(ISNULL(uname,'')) <> ''
   AND uname NOT LIKE N'%주거지역' AND uname NOT LIKE N'%상업지역'
   AND uname NOT LIKE N'%공업지역' AND uname NOT LIKE N'%녹지지역'
 GROUP BY uname ORDER BY COUNT(*) DESC;
