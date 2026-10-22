/* 314: AI 검색 조건 요약표(312) 전부 다시 세기 — 일꾼(_job_runner)이 적재가 끝날 때마다 병렬 줄(z-askattr-par)로 부른다. 약 20분.
   ★ 범위마다 다 센 뒤 짧은 거래 안에서 바꿔 끼우므로, 도는 동안에도 AI 검색은 앞 값이나 새 값 중 하나를 본다(빈 칸 없음). */
SET NOCOUNT ON;
EXEC gold.usp_refresh_ask_attr;
SELECT 표, 굳힌때, 행수 FROM gold.ask_attr_meta ORDER BY 표;
