-- 013 (2026-10-29 밤 QA) 전국 자료 확대 뒤에도 서비스DB 에 **옛 값** 으로 남은 단지별 응답 — '상세 다시'(012)는 detail 만 다시 담는다.
--   부산 거제동월드메르디앙: 어린이집 '안 받음'(받은곳 4,259 = 서울 때 값) · 토지이용계획 '안 받음' 이었다 — 지금 적재DB 에는 전국이 있다.
--   그 종류만 지운다(파생 사본) → 다음 요청은 적재DB 경로가 지금 값으로 답하고 그 답을 다시 담는다(지나며 담기).
--   종류: childcare(어린이집 전국) · landuse · landuse-shape(토지이용계획 20세대+) · closed · history(철거 단지 33만 → 200만)
DELETE FROM svc.complex_json
 WHERE kind IN ('childcare', 'landuse', 'landuse-shape', 'closed', 'history')
   AND updated_at < timestamptz '2026-10-29 12:35:00+09';
