/* academy-bg 가 2628(truncation, zip_no '13551')로 죽었다.
   205_academy.sql 의 DDL 은 이미 VARCHAR(10) 으로 고쳐져 있는데,
   ★ 그 CREATE TABLE 이 **IF NOT EXISTS 로 막혀 있어** 이미 있는 표에는 안 먹었다.
   → **DDL 파일을 고치는 것과 돌아가는 표를 고치는 것은 다른 일이다.**
   먼저 실제 칸을 재고(아래), 좁으면 248 로 ALTER 한다. */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 칸 = STRING_AGG(CAST(CONCAT(COLUMN_NAME, ' ', DATA_TYPE, '(',
              ISNULL(CAST(CHARACTER_MAXIMUM_LENGTH AS VARCHAR(10)), '-'), ')') AS NVARCHAR(MAX)), N'
')
  FROM INFORMATION_SCHEMA.COLUMNS
 WHERE TABLE_SCHEMA = 'silver' AND TABLE_NAME = 'academy'
   AND COLUMN_NAME IN ('zip_no','aca_asnum','tel_no','road_addr','road_addr_dtl',
                       'le_crse_list_nm','thcc_cntnt','realm_sc_nm','le_ord_nm','le_crse_nm');
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 행수 = COUNT(*) FROM silver.academy;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* zip_no 에 색인이 걸려 있으면 ALTER 가 막힐 수 있다 — 미리 본다 */
SELECT 색인 = ISNULL(STRING_AGG(CAST(i.name AS NVARCHAR(MAX)), N', '), '(zip_no 에 색인 없음)')
  FROM sys.indexes i
  JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
  JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
 WHERE i.object_id = OBJECT_ID('silver.academy') AND c.name = 'zip_no';
