SET NOCOUNT ON;
SELECT j = (SELECT r.session_id, 초 = r.total_elapsed_time / 1000, r.dop, r.cpu_time, r.logical_reads, r.reads, ib.event_info
  FROM sys.dm_exec_requests r CROSS APPLY sys.dm_exec_input_buffer(r.session_id, NULL) ib
 WHERE r.session_id <> @@SPID AND r.session_id > 50 FOR JSON PATH);
