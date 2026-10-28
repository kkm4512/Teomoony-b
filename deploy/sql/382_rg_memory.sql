/* 382 화면 쿼리 메모리 몫 — Resource Governor 보강 (2026-10-29 아침)
   ★ 본 것: 적재(etl 풀)가 쿼리 메모리 목표를 거의 다 가져가(1,865MB) default 풀(web 그룹 = 화면)의 목표가 125MB 로 줄었다.
     화면 상세 쿼리는 130MB 를 달라고 하다가 RESOURCE_SEMAPHORE 로 40초씩 줄을 섰다 — 발행(상세 다시) 느림 · HTTP 500.
   ★ 처방: default 풀에 최소 25% · etl 풀은 최대 75%. CPU 쪽(350)은 그대로.
   ★ 얻는 것: 적재가 아무리 커도 화면 쿼리 메모리가 바닥나지 않는다 / 잃는 것: 적재 쿼리 하나가 쓸 수 있는 메모리 상한이 조금 준다.
   ★ 되돌리기: ALTER RESOURCE POOL [default] WITH (MIN_MEMORY_PERCENT = 0); ALTER RESOURCE POOL etl WITH (MAX_MEMORY_PERCENT = 100); ALTER RESOURCE GOVERNOR RECONFIGURE; */
USE master;
ALTER RESOURCE POOL [default] WITH (MIN_MEMORY_PERCENT = 25);
ALTER RESOURCE POOL etl WITH (MAX_MEMORY_PERCENT = 75);
ALTER RESOURCE GOVERNOR RECONFIGURE;
SELECT x = (SELECT STRING_AGG(CONCAT('pool', pool_id, '/', resource_semaphore_id, ' t', target_memory_kb/1024, ' w', waiter_count, ' g', grantee_count), ' | ') FROM sys.dm_exec_query_resource_semaphores);
