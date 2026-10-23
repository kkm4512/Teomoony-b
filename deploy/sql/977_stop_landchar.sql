/* 977 — 토지특성 수집(zz-landchar3-bg) 멈추기: 그 적재기의 DB 연결만 끊는다 (2026-10-23 17:30 사장님 "너 의견대로해" — 화면에 안 쓰는 데이터라 보류)
   ★ 커밋 안 된 마지막 묶음(최대 500필지)은 되돌려진다 — 나중에 --skip-loaded 로 이어 받으면 된다. */
SET NOCOUNT ON;
DECLARE @t TABLE (spid INT, prog NVARCHAR(200), 글 NVARCHAR(200));
INSERT INTO @t
SELECT s.session_id, s.program_name, LEFT(t.text, 200)
  FROM sys.dm_exec_connections c JOIN sys.dm_exec_sessions s ON s.session_id = c.session_id
 CROSS APPLY sys.dm_exec_sql_text(c.most_recent_sql_handle) t
 WHERE s.session_id <> @@SPID AND t.text LIKE N'%silver.land_char%' AND t.text NOT LIKE N'%977 — 토지특성%';
DECLARE @s INT, @q NVARCHAR(40);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT spid FROM @t;
OPEN c; FETCH NEXT FROM c INTO @s;
WHILE @@FETCH_STATUS = 0 BEGIN SET @q = N'KILL ' + CAST(@s AS NVARCHAR(10)); EXEC (@q); FETCH NEXT FROM c INTO @s; END
CLOSE c; DEALLOCATE c;
SELECT j = (SELECT * FROM @t FOR JSON PATH);
