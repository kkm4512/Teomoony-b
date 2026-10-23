SET NOCOUNT ON;
SELECT j = (SELECT s.program_name, s.status, n = COUNT(*), 열린트랜 = SUM(s.open_transaction_count), 요청중 = SUM(CASE WHEN r.session_id IS NULL THEN 0 ELSE 1 END),
                   최장초 = MAX(r.total_elapsed_time) / 1000, 대기 = MAX(r.wait_type), 막힘 = MAX(r.blocking_session_id)
              FROM sys.dm_exec_sessions s LEFT JOIN sys.dm_exec_requests r ON r.session_id = s.session_id
             WHERE s.is_user_process = 1 AND s.session_id <> @@SPID
             GROUP BY s.program_name, s.status FOR JSON PATH);
