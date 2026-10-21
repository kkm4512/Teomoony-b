/* 191. 노선명이 제각각이다 — 실태 (2026-10-19) 읽기 전용 */
SET NOCOUNT ON;
PRINT '--- 노선명 47개 전부 (역수 · 노선번호) ---';
SELECT 노선명 = '[' + line_nm + ']', 노선번호 = MIN(line_cd),
       역 = COUNT(*), 운영 = MIN(oper_nm)
  FROM silver.subway_station WHERE is_current = 1
 GROUP BY line_nm ORDER BY line_nm;
