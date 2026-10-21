/* 256 에서 COUNT(*) 로 63ms 를 재고 "쿼리는 빠르다" 고 했는데, 엔드포인트는 60초다.
   ★★ `COUNT(*)` 는 **뷰가 계산하는 칸을 건너뛸 수 있다.** gold.v_lawd_map 의
     complex_cnt · hhld_cnt · max_amount · trade_cnt 는 집계로 보인다 —
     세기만 하면 옵티마이저가 그 계산을 **통째로 생략**한다.
     그래서 **엔드포인트가 뽑는 칸 그대로** 다시 잰다. 이게 진짜 비용이다.
   ★ 교훈 후보: 느린 것을 잴 때 COUNT(*) 로 재면 거짓으로 빠르다. */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 변형 = 'A COUNT(*) 만', 행 = COUNT(*)
  FROM gold.v_lawd_map v
 WHERE bbox_minx <= 127.1 AND bbox_maxx >= 126.9
   AND bbox_miny <= 37.65 AND bbox_maxy >= 37.5;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* B — 엔드포인트가 뽑는 칸 그대로(geojson 제외). 합으로 받아 전송량은 뺀다. */
SELECT 변형 = 'B 실제 칸', 행 = COUNT(*),
       단지합 = SUM(CAST(complex_cnt AS BIGINT)),
       세대합 = SUM(CAST(hhld_cnt AS BIGINT)),
       거래합 = SUM(CAST(trade_cnt AS BIGINT)),
       최고 = MAX(max_amount)
  FROM gold.v_lawd_map v
 WHERE bbox_minx <= 127.1 AND bbox_maxx >= 126.9
   AND bbox_miny <= 37.65 AND bbox_maxy >= 37.5;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* C — 엔드포인트와 **똑같이** 상관 스칼라 서브쿼리까지 */
SELECT 변형 = 'C 실제 칸 + geojson 서브쿼리', 행 = COUNT(*), 바이트 = SUM(CAST(DATALENGTH(x.gj) AS BIGINT))
  FROM (
    SELECT complex_cnt, hhld_cnt, trade_cnt, max_amount,
           gj = (SELECT geojson FROM silver.lawd_boundary b
                  WHERE b.is_current = 1 AND b.lawd_cd = v.lawd_cd)
      FROM gold.v_lawd_map v
     WHERE bbox_minx <= 127.1 AND bbox_maxx >= 126.9
       AND bbox_miny <= 37.65 AND bbox_maxy >= 37.5
  ) x;
