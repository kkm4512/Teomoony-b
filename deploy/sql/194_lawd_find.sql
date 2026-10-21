/* 194b. 안양/양재 법정동 코드 (2026-10-19) — 읽기 전용 */
SET NOCOUNT ON;
PRINT '--- meta.lawd_code 컬럼 ---';
SELECT name, TYPE_NAME(user_type_id) t FROM sys.columns
 WHERE object_id = OBJECT_ID('meta.lawd_code') ORDER BY column_id;
PRINT '';
PRINT '--- 보유 건수 / 시도 범위 ---';
SELECT 건수 = COUNT(*) FROM meta.lawd_code;
