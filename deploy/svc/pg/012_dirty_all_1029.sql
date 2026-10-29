-- 012 (2026-10-29) 전국 자료 확대 뒤 발행된 상세 전부 '상세 다시' — 값은 안 고친다. cl-svc-dirty-par(6시간마다 :50) 가 세대 많은 곳부터 비운다.
--   바뀐 원천: 청약 전국 · 위반건축물(20세대+) · 폐쇄대장 허브판(철거 단지 33만 → 200만) · 관리비 전국 · 토지특성/이용계획 · 학교알리미 · 어린이집 · 인허가 허브판
INSERT INTO svc.detail_dirty (complex_id, why)
SELECT DISTINCT complex_id, '전국 자료 확대(10-29)' FROM svc.complex_json WHERE kind = 'detail'
ON CONFLICT (complex_id) DO NOTHING;
DELETE FROM svc.resp_cache;   -- 지나며 담은 응답(파생 캐시) — 다음 요청이 지금 값으로 다시 담는다
