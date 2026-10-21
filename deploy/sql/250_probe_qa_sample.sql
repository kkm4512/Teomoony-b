/* QA 표본. ★ 앞서 245(BETWEEN 20 AND 120)에서 뽑은 목록을 그대로 QA 에 써서
   '호 120개 단지가 여섯'이라는 **내가 만든 편향**을 버그로 의심했다.
   그래서 호 수 구간을 **골고루** 뽑는다. 적재가 된 구(성북 11290 · 종로 11110)에서. */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
WITH 호수 AS (
  SELECT complex_id, 호 = COUNT(*) FROM gold.v_complex_ho GROUP BY complex_id
), 붙 AS (
  SELECT c.complex_id, c.complex_nm, c.sigungu_cd, 호 = ISNULL(h.호, 0),
         구간 = CASE WHEN ISNULL(h.호,0) = 0 THEN '0'
                     WHEN h.호 < 30   THEN '1-29'
                     WHEN h.호 < 150  THEN '30-149'
                     WHEN h.호 < 600  THEN '150-599'
                     ELSE '600+' END
    FROM gold.complex c
    LEFT JOIN 호수 h ON h.complex_id = c.complex_id
   WHERE c.sigungu_cd IN ('11290','11110')
), 뽑 AS (
  SELECT *, rn = ROW_NUMBER() OVER (PARTITION BY 구간 ORDER BY complex_id) FROM 붙
)
SELECT 표본 = STRING_AGG(CAST(CONCAT(complex_id,'|',complex_nm,'|',호,'|',구간) AS NVARCHAR(MAX)), N'
')
  FROM 뽑 WHERE rn <= 3;
