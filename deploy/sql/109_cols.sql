/* 109_cols : 컬럼을 추측하지 않고 묻는다 (읽기 전용) */
USE Teomoony;
GO
SET NOCOUNT ON;
GO
SELECT TABLE_SCHEMA+'.'+TABLE_NAME AS tbl,
       cols = STRING_AGG(COLUMN_NAME, ', ') WITHIN GROUP (ORDER BY ORDINAL_POSITION)
  FROM INFORMATION_SCHEMA.COLUMNS
 WHERE (TABLE_SCHEMA='silver' AND TABLE_NAME IN
          ('bld_expos','bld_flr_outline','bld_hsprc','bld_basis_outline'))
    OR (TABLE_SCHEMA='meta' AND TABLE_NAME='ingest_run')
 GROUP BY TABLE_SCHEMA, TABLE_NAME ORDER BY tbl;
GO
