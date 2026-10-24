SET NOCOUNT ON;
/* 340 원문 압축 뒤 — 평문이 비며 생긴 빈 LOB 페이지를 모은다(파일은 줄이지 않는다 — 안에서 다시 쓴다) */
ALTER INDEX pk_api_payload ON bronze.api_payload REORGANIZE WITH (LOB_COMPACTION = ON);
GO
SELECT 종류 = au.type_desc, mb = SUM(au.total_pages)/128, 쓰는mb = SUM(au.used_pages)/128
  FROM sys.partitions p JOIN sys.allocation_units au ON au.container_id = p.partition_id
 WHERE p.object_id = OBJECT_ID('bronze.api_payload') GROUP BY au.type_desc;
SELECT 남은평문 = COUNT_BIG(*) FROM bronze.api_payload WHERE body IS NOT NULL;
