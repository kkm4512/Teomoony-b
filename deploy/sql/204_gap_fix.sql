/* =====================================================================
   meta.v_load_page_gap — **없는 것**과 **실패한 것**을 가른다 (2026-10-20)

   ★ 첫 실행에서 53 곳이 "실패 1" 로 찍혔다. 전부 **건수 0 인 법정동**이었다
     (종로구의 작은 동들처럼 주택이 아예 없는 곳). 받았는데 비어 있는 것은
     EMPTY 이지 FAIL 이 아니다. 둘을 한 칸에 적으면 **진짜 실패가 묻힌다** —
     이 프로젝트의 GAP 어휘(SCOPE / NA / UNSURE)가 있는 이유 그대로다.
   ===================================================================== */
USE Teomoony;
GO
CREATE OR ALTER VIEW meta.v_load_page_gap
AS
SELECT sgg_cd, bjdong_cd, op,
       받은페이지 = COUNT(*),
       최대페이지 = MAX(page),
       /* 1..최대 중 **번호가 빠진 수**. 0 이어야 정상이다. */
       빠진페이지 = MAX(page) - COUNT(*),
       /* 받았는데 비어 있던 쪽. 주택이 없는 동이면 **정상**이다 (NA). */
       빈쪽 = SUM(CASE WHEN status = 'EMPTY' THEN 1 ELSE 0 END),
       /* 진짜 실패. 이것만 0 이 아니면 봐야 한다. */
       실패 = SUM(CASE WHEN status = 'FAIL' THEN 1 ELSE 0 END),
       api_total = MAX(api_total),
       받은건수 = SUM(items)
  FROM meta.load_page
 GROUP BY sgg_cd, bjdong_cd, op;
GO
PRINT '204_gap_fix 완료';
GO
