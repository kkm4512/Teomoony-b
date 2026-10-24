-- 10-25: 점검 스크립트가 트랜잭션을 연 채로 30분 머물러(읽은 표에 잠금) 매시 발행의 표 바꿔 끼우기(DROP)가 멈췄다 → 그 뒤로 화면 읽기도 줄을 섰다.
-- 열어 둔 채 노는 트랜잭션은 2분이면 끊는다(서비스DB 에서 그렇게 오래 쥘 일이 없다).
ALTER DATABASE teomoony SET idle_in_transaction_session_timeout = '2min';
SELECT pg_terminate_backend(pid) FROM pg_stat_activity
 WHERE datname = 'teomoony' AND state = 'idle in transaction' AND now() - state_change > interval '1 minute';
