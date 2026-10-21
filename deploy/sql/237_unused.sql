/* 237_unused : 표와 대략 행수를 한 줄로 묶어 본다 (2026-10-21) 읽기만.
   ★ COUNT(*) 를 치지 않는다 — 적재 중이라 비싸다. 파티션 통계로 근사한다. */
USE Teomoony;
GO
SELECT 목록 = STRING_AGG(CAST(표 + '=' + CAST(행수 AS VARCHAR(20)) AS NVARCHAR(MAX)), ' | ')
              WITHIN GROUP (ORDER BY 행수 DESC)
  FROM (
    SELECT 표 = s.name + '.' + t.name,
           행수 = SUM(CASE WHEN p.index_id IN (0,1) THEN p.row_count ELSE 0 END)
      FROM sys.tables t
      JOIN sys.schemas s ON s.schema_id = t.schema_id
      JOIN sys.dm_db_partition_stats p ON p.object_id = t.object_id
     WHERE s.name IN ('silver','gold','meta','ops')
     GROUP BY s.name, t.name
    HAVING SUM(CASE WHEN p.index_id IN (0,1) THEN p.row_count ELSE 0 END) > 0
  ) q;
GO
