SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT s.name + '.' + t.name, 줄 = SUM(p.rows) FROM sys.tables t JOIN sys.schemas s ON s.schema_id = t.schema_id JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
 WHERE s.name = 'hub' GROUP BY s.name, t.name ORDER BY 1;
SELECT s.name + '.' + v.name FROM sys.views v JOIN sys.schemas s ON s.schema_id = v.schema_id WHERE s.name = 'hubv';
IF OBJECT_ID('hub.load_done') IS NOT NULL SELECT TOP 30 * FROM hub.load_done ORDER BY 1 DESC;
SELECT 이름, 작업, 주기, 켜짐, 근거, 메모 FROM ops.collect_schedule WHERE 자료 LIKE N'%건축%' OR 자료 LIKE N'%대장%' OR 이름 LIKE N'%대장%' OR 이름 LIKE N'%인허가%';
SELECT TOP 3 처음월, 마지막월, n = COUNT(*) FROM hub.t0303 GROUP BY 처음월, 마지막월 ORDER BY 3 DESC;
