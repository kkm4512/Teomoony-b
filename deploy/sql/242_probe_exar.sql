/* 전용률(계약면적 기준) 작업용 probe. 아무것도 바꾸지 않는다 — 읽기만.
   ★ 집계 안에 서브쿼리 금지 — 첫 판에서 STRING_AGG 안에 스칼라 서브쿼리를 넣어
     바로 터졌다. 전체호를 **별도 CTE 로 미리 센 뒤** 조인한다. */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

WITH 공용호 AS (
  SELECT mgm_bldrgst_pk
    FROM silver.bld_expos_pubuse_area
   WHERE is_current = 1 AND expos_pubuse_gb_cd = '2'
   GROUP BY mgm_bldrgst_pk
), 공용 AS (
  SELECT TOP 6 h.complex_id, 공용있는호 = COUNT(*)
    FROM gold.v_complex_ho h
    JOIN 공용호 g ON g.mgm_bldrgst_pk = h.호PK
   GROUP BY h.complex_id
   ORDER BY COUNT(*) DESC
), 전체 AS (
  SELECT v.complex_id, 전체호 = COUNT(*)
    FROM gold.v_complex_ho v
    JOIN 공용 d2 ON d2.complex_id = v.complex_id
   GROUP BY v.complex_id
)
SELECT 기준단지 = STRING_AGG(CAST(CONCAT(d.complex_id, '(', c.complex_nm, ') 공용있는호 ',
                                         d.공용있는호, ' / 전체호 ', t.전체호) AS NVARCHAR(MAX)), N'
')
  FROM 공용 d
  JOIN 전체 t ON t.complex_id = d.complex_id
  JOIN gold.complex c ON c.complex_id = d.complex_id;

SELECT 색인 = STRING_AGG(CAST(CONCAT(i.name, ' = ', c.칸) AS NVARCHAR(MAX)), N'
')
  FROM sys.indexes i
 CROSS APPLY (SELECT 칸 = STRING_AGG(CAST(col.name AS NVARCHAR(MAX)), ',')
                             WITHIN GROUP (ORDER BY ic.key_ordinal)
                FROM sys.index_columns ic
                JOIN sys.columns col ON col.object_id = ic.object_id
                                    AND col.column_id = ic.column_id
               WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id
                 AND ic.is_included_column = 0) c
 WHERE i.object_id = OBJECT_ID('silver.bld_expos_pubuse_area') AND i.name IS NOT NULL;
