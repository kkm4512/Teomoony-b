/* 410 (2026-11-10 사장님 "1번 줄이고 3번 하고") 일회용 실행계획 · 병렬 문턱
   ★ 본 것(16:53): 실행계획 캐시(CACHESTORE_SQLCP) 2,048MB — 적재 코드가 값을 SQL 글자에 넣어 보내 한 번 쓰고 버리는 계획이 쌓임. 버퍼 풀 4,165MB.
   ① optimize for ad hoc workloads = 1 : 처음 온 쿼리는 계획 껍데기만 두고, 두 번째 올 때 온전히 담는다.
      얻는 것: 캐시 2GB 대부분이 데이터 캐시로 · 잃는 것: 두 번째에 계획을 한 번 더 만든다(무시할 만함).
   ② cost threshold for parallelism 5 → 50 : 중간 크기 쿼리는 한 코어로. 큰 집계는 그대로 병렬.
      얻는 것: 병렬 쪼개기 CPU 낭비 ↓ · 잃는 것: 문턱 근처 일부 쿼리가 조금 느려질 수 있다.
   ★ 서버 MAXDOP 는 그대로(0): 적재는 이미 350 Resource Governor 'etl' 그룹 MAX_DOP 4 · CAP 70%. 서버 MAXDOP 를 낮추면 영향받는 건 화면(web)뿐.
   ③ 쌓여 있던 일회용 계획만 비운다(DBCC FREESYSTEMCACHE 'SQL Plans' — 프로시저 계획 'Object Plans' 는 남김).
   되돌리기: sp_configure 'optimize for ad hoc workloads', 0 · sp_configure 'cost threshold for parallelism', 5 · RECONFIGURE */
SELECT 전_계획캐시MB = (SELECT SUM(pages_kb)/1024 FROM sys.dm_os_memory_clerks WHERE type = 'CACHESTORE_SQLCP'),
       전_버퍼MB = (SELECT SUM(pages_kb)/1024 FROM sys.dm_os_memory_clerks WHERE type = 'MEMORYCLERK_SQLBUFFERPOOL');
GO
EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
EXEC sp_configure 'optimize for ad hoc workloads', 1;
EXEC sp_configure 'cost threshold for parallelism', 50;
RECONFIGURE;
GO
DBCC FREESYSTEMCACHE ('SQL Plans') WITH NO_INFOMSGS;
GO
SELECT name, 지금값 = CAST(value_in_use AS int) FROM sys.configurations
 WHERE name IN ('optimize for ad hoc workloads', 'cost threshold for parallelism', 'max degree of parallelism');
SELECT 후_계획캐시MB = (SELECT SUM(pages_kb)/1024 FROM sys.dm_os_memory_clerks WHERE type = 'CACHESTORE_SQLCP');
