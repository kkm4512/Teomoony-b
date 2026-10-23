/* 985 — 단지 상세가 30초 넘게 걸림(2026-10-23 19:5x): 같은 쿼리가 따로 돌리면 0.7초 · 서버 캐시 계획만 느림(계획 퇴행) →
   v_complex_ho 를 쓰는 **그 쿼리들의 캐시 계획만** 버린다(데이터 · 설정은 안 건드림). */
SET NOCOUNT ON;
DECLARE @h TABLE (ph VARBINARY(64), ms BIGINT, 글 NVARCHAR(200));
INSERT INTO @h SELECT DISTINCT qs.plan_handle, qs.last_elapsed_time / 1000, LEFT(st.text, 200)
  FROM sys.dm_exec_query_stats qs CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
 WHERE st.text LIKE N'%gold.v_complex_ho%' AND st.text NOT LIKE N'%985 — %';
DECLARE @p VARBINARY(64);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT ph FROM @h;
OPEN c; FETCH NEXT FROM c INTO @p;
WHILE @@FETCH_STATUS = 0 BEGIN DBCC FREEPROCCACHE (@p) WITH NO_INFOMSGS; FETCH NEXT FROM c INTO @p; END
CLOSE c; DEALLOCATE c;
SELECT j = (SELECT 버림 = COUNT(DISTINCT ph), 최근ms = (SELECT ms, 글 = LEFT(글, 80) FROM @h ORDER BY ms DESC FOR JSON PATH) FROM @h FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
