SET NOCOUNT ON;
SELECT j = (SELECT r.session_id, 초 = r.total_elapsed_time / 1000, r.logical_reads,
       지금 = SUBSTRING(t.text, r.statement_start_offset / 2 + 1, 300),
       s.ansi_nulls, s.arithabort, s.quoted_identifier, s.ansi_warnings, s.concat_null_yields_null, s.date_format, s.language, s.transaction_isolation_level
  FROM sys.dm_exec_requests r CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t JOIN sys.dm_exec_sessions s ON s.session_id = r.session_id
 WHERE r.session_id <> @@SPID AND r.total_elapsed_time > 3000 AND r.session_id > 50 AND t.text NOT LIKE N'%ned_aphus%' FOR JSON PATH);
