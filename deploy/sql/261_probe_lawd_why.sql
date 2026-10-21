/* 범위 비교가 LEFT 보다 **더 느렸다**(2,195ms vs 1,439ms). 의외라 쪼갠다.
   가설: 색인 ix_rtms_pnu(match_pnu) 로 찾기는 하는데, deal_amount·면적 같은 칸이
   그 색인에 **없어서** 행마다 클러스터로 되돌아가는 비용(키 조회)이 크다.
   → 색인에 든 칸만 세면 빨라야 한다. 그러면 답은 **덮는 색인**이다. */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @l CHAR(10) = '1129013800';
SELECT 변형='A 색인 칸만(match_pnu)', 건수 = COUNT(*)
  FROM silver.rtms_trade r
 WHERE r.match_pnu >= @l + '000000000' AND r.match_pnu <= @l + '999999999';
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @l2 CHAR(10) = '1129013800';
SELECT 변형='B + 거름칸(is_rent·취소)', 건수 = COUNT(*)
  FROM silver.rtms_trade r
 WHERE r.match_pnu >= @l2 + '000000000' AND r.match_pnu <= @l2 + '999999999'
   AND r.is_rent = 0 AND r.is_canceled = 0;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @l3 CHAR(10) = '1129013800';
SELECT 변형='C + 금액까지(지금 뷰가 쓰는 것)', 건수 = COUNT(*), 최고 = MAX(deal_amount)
  FROM silver.rtms_trade r
 WHERE r.match_pnu >= @l3 + '000000000' AND r.match_pnu <= @l3 + '999999999'
   AND r.is_rent = 0 AND r.is_canceled = 0 AND r.deal_amount IS NOT NULL;
