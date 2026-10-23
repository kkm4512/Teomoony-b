SET NOCOUNT ON;
DECLARE @s INT = (SELECT TOP 1 r.session_id FROM sys.dm_exec_requests r CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
                   WHERE t.text LIKE N'%970 — 좌표 없는 폐쇄 자리%' AND t.text NOT LIKE N'%KILL%' AND r.session_id <> @@SPID);
IF @s IS NOT NULL EXEC (N'KILL ' + @s);
SELECT 죽임 = @s;
