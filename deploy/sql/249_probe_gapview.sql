/* meta.v_load_page_gap 의 칸을 본다 — 적재 진행 판정 공식을 **두 번 쓰지 않으려고**.
   (/api/_prog 안에 같은 공식이 인라인으로 박혀 있다. 뷰가 쓸 수 있으면 둘 다 뷰를 본다.) */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 있나 = CASE WHEN OBJECT_ID('meta.v_load_page_gap') IS NULL THEN 0 ELSE 1 END;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 칸 = STRING_AGG(CAST(CONCAT(COLUMN_NAME,' ',DATA_TYPE) AS NVARCHAR(MAX)), N', ')
  FROM INFORMATION_SCHEMA.COLUMNS
 WHERE TABLE_SCHEMA='meta' AND TABLE_NAME='v_load_page_gap';
