-- 10-25: 03~06시 매시 발행 4번이 서비스DB 의 '열어 둔 트랜잭션 2분 끊기'(004)에 걸려 죽었다 → 'running' 으로 남은 것을 failed 로(기록).
UPDATE svc.publish SET status = 'failed', finished_at = now(), note = coalesce(note, '') || ' · 열어 둔 트랜잭션 2분 끊김(004)에 걸려 죽음 — 10-25 07시 정리'
 WHERE status = 'running' AND publish_id BETWEEN 10 AND 13;
