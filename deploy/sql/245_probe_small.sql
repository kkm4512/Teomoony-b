/* 화면 확인용 **작은** 단지. builds(공간조인)가 60초를 넘겨 큰 단지로는 확인이 막혔다.
   공용 면적이 있고 호가 적은 단지를 고른다. */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
WITH 공용호 AS (
  SELECT mgm_bldrgst_pk FROM silver.bld_expos_pubuse_area
   WHERE is_current = 1 AND expos_pubuse_gb_cd = '2'
   GROUP BY mgm_bldrgst_pk
), 단지 AS (
  SELECT h.complex_id, 공용있는호 = COUNT(*)
    FROM gold.v_complex_ho h
    JOIN 공용호 g ON g.mgm_bldrgst_pk = h.호PK
   GROUP BY h.complex_id
   HAVING COUNT(*) BETWEEN 20 AND 120
)
SELECT 작은단지 = STRING_AGG(CAST(CONCAT(d.complex_id, '(', c.complex_nm, ') ', d.공용있는호, '호') AS NVARCHAR(MAX)), N'
')
  FROM (SELECT TOP 8 * FROM 단지 ORDER BY 공용있는호 DESC) d
  JOIN gold.complex c ON c.complex_id = d.complex_id;
