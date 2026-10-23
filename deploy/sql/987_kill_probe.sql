SET NOCOUNT ON;
DECLARE @s INT = (SELECT TOP 1 r.session_id FROM sys.dm_exec_requests r CROSS APPLY sys.dm_exec_input_buffer(r.session_id, NULL) ib
                   WHERE ib.event_info LIKE N'%SET ARITHABORT OFF%' AND ib.event_info NOT LIKE N'%987%' AND r.session_id <> @@SPID);
IF @s IS NOT NULL EXEC (N'KILL ' + @s);
SELECT 죽임 = @s;
