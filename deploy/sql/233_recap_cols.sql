/* 233_recap_cols : 총괄표제부에 어떤 칸이 있나 (2026-10-20) 읽기만. DDL 을 추측하지 않는다. */
USE Teomoony;
GO
SELECT 칸 = STRING_AGG(COLUMN_NAME, ', ') WITHIN GROUP (ORDER BY ORDINAL_POSITION)
  FROM INFORMATION_SCHEMA.COLUMNS
 WHERE TABLE_SCHEMA = 'silver' AND TABLE_NAME = 'bld_recap_title';
GO
