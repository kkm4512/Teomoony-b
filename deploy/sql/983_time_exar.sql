SET NOCOUNT ON; SET ARITHABORT OFF;
DECLARE @t DATETIME2 = SYSDATETIME();
EXEC sp_executesql N'SELECT 잰호 = SUM(CASE WHEN x.전유 > 0 AND x.공용 > 0 THEN 1 ELSE 0 END), 면적행있는호 = COUNT(*)
        FROM gold.v_complex_ho h
       CROSS APPLY (SELECT 전유 = SUM(CASE WHEN a.expos_pubuse_gb_cd = ''1'' THEN a.area END), 공용 = SUM(CASE WHEN a.expos_pubuse_gb_cd = ''2'' THEN a.area END)
           FROM silver.bld_expos_pubuse_area a WHERE a.mgm_bldrgst_pk = h.호PK AND a.is_current = 1) x
       WHERE h.complex_id = @id AND (x.전유 > 0 OR x.공용 > 0)', N'@id int', @id = 469943;
DECLARE @a INT = DATEDIFF(MILLISECOND, @t, SYSDATETIME());
SELECT j = (SELECT exar_ms = @a,
  계획 = (SELECT TOP 5 qs.execution_count, 평균ms = qs.total_elapsed_time / NULLIF(qs.execution_count, 0) / 1000, 최근ms = qs.last_elapsed_time / 1000, 글 = LEFT(st.text, 120)
           FROM sys.dm_exec_query_stats qs CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
          WHERE st.text LIKE N'%v_complex_ho%' AND st.text NOT LIKE N'%dm_exec_query_stats%' ORDER BY qs.last_elapsed_time DESC FOR JSON PATH)
  FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
