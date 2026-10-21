/* v_lawd_map 이 60초를 넘기는 이유: 아래 조건이 **색인을 못 탄다**.
       LEFT(r.match_pnu, 10) = b.lawd_cd
   칸을 함수로 감싸면 SARGable 이 아니다 → 법정동 126개마다 rtms_trade(1,054만)를 훑는다.
   ★ 고치는 법은 **범위 비교**다: match_pnu BETWEEN lawd+'000000000' AND lawd+'999999999'
     (PNU 는 19자리 고정이라 앞 10자리가 같으면 그 범위 안에 정확히 들어온다.)
   ★ 먼저 **색인이 있는지** 보고, 범위 비교가 실제로 빨라지는지 **재고 나서** 고친다. */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 색인 = STRING_AGG(CAST(CONCAT(i.name,'(',c.칸,')') AS NVARCHAR(MAX)), N'
')
  FROM sys.indexes i
 CROSS APPLY (SELECT 칸 = STRING_AGG(CAST(col.name AS NVARCHAR(MAX)), ',')
                           WITHIN GROUP (ORDER BY ic.key_ordinal)
                FROM sys.index_columns ic
                JOIN sys.columns col ON col.object_id = ic.object_id AND col.column_id = ic.column_id
               WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id
                 AND ic.is_included_column = 0) c
 WHERE i.object_id = OBJECT_ID('silver.rtms_trade') AND i.name IS NOT NULL;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* 한 법정동만 — 지금 식(LEFT) */
DECLARE @l CHAR(10) = '1129013800';
SELECT 변형='지금(LEFT)', 건수 = COUNT(*), 최고 = MAX(deal_amount)
  FROM silver.rtms_trade r
 WHERE r.is_rent = 0 AND r.is_canceled = 0 AND r.deal_amount IS NOT NULL
   AND LEFT(r.match_pnu, 10) = @l;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* 같은 답을 범위 비교로 */
DECLARE @l2 CHAR(10) = '1129013800';
SELECT 변형='고침(범위)', 건수 = COUNT(*), 최고 = MAX(deal_amount)
  FROM silver.rtms_trade r
 WHERE r.is_rent = 0 AND r.is_canceled = 0 AND r.deal_amount IS NOT NULL
   AND r.match_pnu >= @l2 + '000000000' AND r.match_pnu <= @l2 + '999999999';
