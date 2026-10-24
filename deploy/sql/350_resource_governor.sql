/* 350 화면 먼저 — Resource Governor (2026-10-24 20:08 사장님 폰 "터무니 검색 속도가 느리다")
   ★ 원인: 적재(건축HUB 649만 줄 해시 · 토지특성 · 관리비 · 시범 대장 12스레드)가 서버 CPU 12개를 다 쓴다. max degree of parallelism = 0(전부) ·
     비용 문턱 5 라 적재 쿼리 하나가 CPU 12개를 잡고(CXSYNC_PORT), 화면 쿼리는 그 뒤에 줄을 섰다 — 상세 15초 · 홈 수치 16초(폰 실측).
   ★ 처방: 적재 연결(pymssql · SQLCMD)은 'etl' 풀 — 병렬 최대 4 · CPU 가 모자랄 때 60% 까지 · 중요도 낮음.
           화면(node-mssql)은 'web' 그룹 — 중요도 높음. 다툼이 없을 땐 적재도 CPU 를 다 쓴다(CAP 은 다툼 때만이 아니라 상한이지만 60% 는 넉넉).
   ★ 되돌리기: ALTER RESOURCE GOVERNOR DISABLE; (이미 연결된 세션은 다시 붙을 때부터 적용) */
USE master;
GO
IF NOT EXISTS (SELECT 1 FROM sys.resource_governor_resource_pools WHERE name = 'etl')
    CREATE RESOURCE POOL etl WITH (MAX_CPU_PERCENT = 60, CAP_CPU_PERCENT = 70);
GO
IF NOT EXISTS (SELECT 1 FROM sys.resource_governor_workload_groups WHERE name = 'etl')
    CREATE WORKLOAD GROUP etl WITH (IMPORTANCE = LOW, MAX_DOP = 4) USING etl;
GO
IF NOT EXISTS (SELECT 1 FROM sys.resource_governor_workload_groups WHERE name = 'web')
    CREATE WORKLOAD GROUP web WITH (IMPORTANCE = HIGH) USING [default];
GO
CREATE OR ALTER FUNCTION dbo.fn_teomoony_classifier() RETURNS sysname WITH SCHEMABINDING
AS
BEGIN
    DECLARE @a sysname = APP_NAME();
    IF @a LIKE N'node-mssql%' RETURN N'web';
    IF @a LIKE N'pymssql%' OR @a LIKE N'SQLCMD%' RETURN N'etl';
    RETURN N'default';
END
GO
ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = dbo.fn_teomoony_classifier);
ALTER RESOURCE GOVERNOR RECONFIGURE;
GO
SELECT j=(SELECT (SELECT is_enabled FROM sys.resource_governor_configuration) 켜짐,
  (SELECT STRING_AGG(CONCAT(g.name, ':', x.n), ', ') FROM (SELECT group_id, n = COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process = 1 GROUP BY group_id) x JOIN sys.resource_governor_workload_groups g ON g.group_id = x.group_id) 세션 FOR JSON PATH);
GO
