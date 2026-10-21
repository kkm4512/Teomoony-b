USE Teomoony;
GO
SET NOCOUNT ON;
GO
PRINT '--- v_load_plan 정의 ---';
SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID('meta.v_load_plan');
PRINT '--- v_lawd_scope 정의 ---';
SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID('meta.v_lawd_scope');
PRINT '--- lawd_code 컬럼 ---';
SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
 WHERE TABLE_SCHEMA='meta' AND TABLE_NAME='lawd_code' ORDER BY ORDINAL_POSITION;
PRINT '--- 지금 load_target 전체 ---';
SELECT target_id, sgg_cd, bjdong_cd, ops, enabled, note FROM meta.load_target ORDER BY target_id;
GO
