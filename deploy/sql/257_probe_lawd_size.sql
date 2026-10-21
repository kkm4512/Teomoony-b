/* /api/lawds 가 60초 타임아웃인데 쿼리는 25~63ms 다(256 에서 쟀다).
   ★ COUNT(*) 로는 **실어 나르는 양**이 안 드러난다. 경계 geojson 을 126개
     통째로 보내는 비용을 잰다 — 그게 범인인지 가른다. */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 법정동수 = COUNT(*),
       총바이트 = SUM(CAST(DATALENGTH(g.geojson) AS BIGINT)),
       총MB = CAST(SUM(CAST(DATALENGTH(g.geojson) AS BIGINT)) / 1048576.0 AS DECIMAL(10,1)),
       가장큰KB = CAST(MAX(DATALENGTH(g.geojson)) / 1024.0 AS DECIMAL(10,1)),
       평균KB = CAST(AVG(CAST(DATALENGTH(g.geojson) AS BIGINT)) / 1024.0 AS DECIMAL(10,1))
  FROM gold.v_lawd_map v
 OUTER APPLY (SELECT TOP 1 geojson FROM silver.lawd_boundary b
               WHERE b.is_current = 1 AND b.lawd_cd = v.lawd_cd) g
 WHERE bbox_minx <= 127.1 AND bbox_maxx >= 126.9
   AND bbox_miny <= 37.65 AND bbox_maxy >= 37.5;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* 전국(뷰 전체)으로도 — 화면이 넓게 보면 이만큼 나간다 */
SELECT 전체법정동 = COUNT(*),
       총MB = CAST(SUM(CAST(DATALENGTH(g.geojson) AS BIGINT)) / 1048576.0 AS DECIMAL(10,1))
  FROM gold.v_lawd_map v
 OUTER APPLY (SELECT TOP 1 geojson FROM silver.lawd_boundary b
               WHERE b.is_current = 1 AND b.lawd_cd = v.lawd_cd) g;
