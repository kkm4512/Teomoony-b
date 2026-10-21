/* 이용현황을 0 에서 다시 센다 — **사장님이 고른 것**(2026-10-21, 3번안).
   ★ 왜: 10/21 QA 에서 공개 수치에 **내 테스트 호출이 섞여 있던 것**을 발견했다.
     `이용_동작()` 이 `/api/_*`(진단)만 빼고 일반 API 는 호스트를 안 가려서,
     localhost 로 두드린 QA 가 그대로 공개 숫자에 들어갔다(오늘 633회 중 대부분).
     고침은 넣었지만(localhost 제외) **쌓인 1,087 은 소급해서 가를 수 없다.**
   ★ 이건 파생표가 아니라 **기록**이다. 그래서 내가 판단하지 않고 세 가지 안을
     드렸고, 사장님이 "전부 지우고 지금부터 0" 을 골랐다. 되돌릴 수 없다.
   ⚠ 표를 지우지 않고 **행만** 지운다(DROP 아님). 구조·제약은 그대로 둔다. */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 지우기전_행 = COUNT(*), 지우기전_합 = ISNULL(SUM(횟수), 0) FROM ops.usage_hour;
GO
DELETE FROM ops.usage_hour;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 지운뒤_행 = COUNT(*), 지운뒤_합 = ISNULL(SUM(횟수), 0) FROM ops.usage_hour;
