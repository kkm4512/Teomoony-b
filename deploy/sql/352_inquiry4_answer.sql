/* 352: 문의 4(2026-10-25 08:25 단지 54 상세 502) 답변 */
UPDATE ops.inquiry
   SET 답변 = N'알려 주셔서 고맙습니다. 08:25 에 단지 54 상세가 HTTP 502 로 떨어진 것은, 바로 그 순간(08:25:27) 웹 서버가 다시 뜨던 중이라 요청이 서버까지 닿지 못했기 때문입니다(그 요청은 접속 기록에 없고, 서버가 새로 뜬 시각이 08:25:27 입니다). 단지 54 는 지금 정상으로 열립니다.
서버가 왜 그때 다시 떴는지는 아직 못 찾았습니다 — 그 시각에 바뀐 파일이 없었습니다. 그래서 이제 서버가 멈추거나 다시 뜰 때 이유를 기록에 남기고, 처리 못 한 오류 하나 때문에 서버 전체가 내려가지 않게 했습니다.
화면도 고쳤습니다: 서버에 닿지 못한 실패(502·503·504)는 1초 · 3초 뒤에 두 번 더 해 보고, 그래도 안 될 때만 오류 카드를 보여 줍니다. 같은 일이 또 보이면 남겨 주세요.',
       답변때 = SYSDATETIME(),
       답변자 = COALESCE((SELECT TOP 1 답변자 FROM ops.inquiry WHERE 답변자 IS NOT NULL ORDER BY inquiry_id DESC), N'root'),
       상태 = N'답변함'
 WHERE inquiry_id = 4 AND 답변 IS NULL;
SELECT inquiry_id, 상태, 답변자, LEFT(답변, 40) 답변 FROM ops.inquiry WHERE inquiry_id = 4;
