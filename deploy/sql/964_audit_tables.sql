SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT (SELECT 표 = s.name + '.' + t.name, 행 = SUM(p.rows)
          FROM sys.tables t JOIN sys.schemas s ON s.schema_id = t.schema_id
          JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
         WHERE s.name IN ('silver', 'gold', 'meta', 'ops')
         GROUP BY s.name, t.name ORDER BY s.name, t.name FOR JSON PATH) AS j;
