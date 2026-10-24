-- 10-25: 지나며 담기(응답 통째로) — 호 상세 · 주변 지점(?kind=) · 점포 목록(?life=). 주소 하나 = 한 줄.
-- 24시간 지나면 안 쓴다(다시 옛 경로가 답하고 새로 담김) · 그 단지가 바뀌면 매시 발행이 지운다.
CREATE TABLE IF NOT EXISTS svc.resp_cache (
  url        text PRIMARY KEY,
  complex_id int,
  body_gz    bytea NOT NULL,
  bytes      int,
  at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_resp_cache_cid ON svc.resp_cache (complex_id);
