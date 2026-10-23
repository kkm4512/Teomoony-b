SET NOCOUNT ON;
SELECT (SELECT r.session_id, r.status, r.command, r.wait_type, 초 = r.total_elapsed_time / 1000, r.blocking_session_id, 글 = LEFT(t.text, 80), 지금 = LEFT(SUBSTRING(t.text, r.statement_start_offset / 2 + 1, 200), 200)
          FROM sys.dm_exec_requests r CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t WHERE r.session_id <> @@SPID AND r.session_id > 50 FOR JSON PATH) AS j;
