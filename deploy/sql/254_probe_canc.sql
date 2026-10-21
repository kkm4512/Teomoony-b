/* 해제(취소) 거래가 있는 단지를 찾는다 — 화면 확인용.
   ★ 금액이 있는 것과 없는 것을 **둘 다** 찾는다. 금액 없는 해제도 화면이
     '금액 미상' 으로 적는지 봐야 한다(0원으로 적으면 거짓이 된다). */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
WITH x AS (
  SELECT match_complex_id AS cid,
         해제 = SUM(CAST(is_canceled AS INT)),
         해제금액있음 = SUM(CASE WHEN is_canceled = 1 AND deal_amount IS NOT NULL THEN 1 ELSE 0 END),
         해제금액없음 = SUM(CASE WHEN is_canceled = 1 AND deal_amount IS NULL THEN 1 ELSE 0 END)
    FROM silver.rtms_trade
   WHERE match_complex_id IS NOT NULL
   GROUP BY match_complex_id
  HAVING SUM(CAST(is_canceled AS INT)) > 0
)
SELECT 표본 = STRING_AGG(CAST(CONCAT(y.cid,'|',c.complex_nm,'|해제',y.해제,
                                      '|금액있음',y.해제금액있음,'|없음',y.해제금액없음) AS NVARCHAR(MAX)), N'
')
  FROM (SELECT TOP 6 * FROM x ORDER BY 해제금액없음 DESC, 해제 DESC) y
  JOIN gold.complex c ON c.complex_id = y.cid;
