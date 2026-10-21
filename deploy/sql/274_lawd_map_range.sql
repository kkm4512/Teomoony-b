/* 274. v_lawd_map — 앞자리 비교를 **범위**로 (2026-10-21, 273 이어서)
   ★ 273 에서 LIKE lawd_cd + '%' 로 바꿨는데 **색인 범위탐색을 안 탔다**(실측, 3개 법정동):
       LIKE                     5,260ms
       범위 CHAR(19)              122ms   ← 이것
       범위 + 색인 지정            70ms   (힌트는 깨지기 쉬워 안 쓴다)
     값(trade_cnt · max_amount · max_area · max_ymd)은 넷 다 같다.
     ★ 교훈: 'SARGable 하게 바꿨다' 는 **잰 뒤에** 말한다. LIKE 의 앞자리 탐색은 상수일 때는
       되지만 APPLY 안의 열 값으로 만든 무늬에서는 안 됐다.
   ★ 단지 쪽(gold.complex)도 LEFT(rep_pnu,10) 라 표를 훑는다(3개 법정동 340ms) →
     rep_pnu 색인 + 같은 범위 비교. gold.complex 는 파생 표라 색인을 더해도 된다.
   ★ 범위: lawd_cd + '000000000' ~ lawd_cd + '999999999' (PNU 19 = 법정동 10 + 숫자 9).
     PNU 뒷자리는 숫자뿐이라 이 범위가 LEFT(...,10) = lawd_cd 와 같은 집합이다.
   ★ 다시 돌려도 된다. */
SET NOCOUNT ON;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_complex_rep_pnu' AND object_id = OBJECT_ID('gold.complex'))
    CREATE INDEX ix_complex_rep_pnu ON gold.complex (rep_pnu) INCLUDE (dong_cnt, hhld_cnt_sum)
        WITH (MAXDOP = 4);
GO
CREATE OR ALTER VIEW gold.v_lawd_map
AS
SELECT
    b.lawd_cd, b.emd_nm, b.full_nm, b.sgg_cd,
    b.centroid_lat, b.centroid_lng,
    b.bbox_minx, b.bbox_miny, b.bbox_maxx, b.bbox_maxy,
    cx.complex_cnt, cx.dong_cnt, cx.hhld_cnt,
    t.max_amount, t.max_area, t.max_ymd, t.trade_cnt
FROM silver.lawd_boundary b
/* 274: PNU 앞 10자리 범위 - 아래 두 APPLY 가 같이 쓴다 */
CROSS APPLY (SELECT 하 = CAST(CAST(b.lawd_cd AS VARCHAR(10)) + '000000000' AS CHAR(19)),
                    상 = CAST(CAST(b.lawd_cd AS VARCHAR(10)) + '999999999' AS CHAR(19))) k
OUTER APPLY (
    SELECT COUNT(*) AS complex_cnt,
           SUM(c.dong_cnt) AS dong_cnt,
           SUM(c.hhld_cnt_sum) AS hhld_cnt
    FROM gold.complex c
    WHERE c.rep_pnu >= k.하 AND c.rep_pnu <= k.상
) cx
OUTER APPLY (
    SELECT COUNT(*) AS trade_cnt,
           MAX(r.deal_amount) AS max_amount,
           MAX(CASE WHEN r.rn = 1 THEN r.area END)     AS max_area,
           MAX(CASE WHEN r.rn = 1 THEN r.deal_ymd END) AS max_ymd
    FROM (
        SELECT r.deal_amount, r.deal_ymd,
               /* 273: building_ar 추가 - 상세 실거래 카드와 같은 순서 */
               CAST(FLOOR(COALESCE(r.exclu_use_ar, r.total_floor_ar, r.building_ar)) AS INT) AS area,
               ROW_NUMBER() OVER (ORDER BY r.deal_amount DESC) AS rn
        FROM silver.rtms_trade r
        /* 273: ix_rtms_lawd_trade 의 거름과 같게 · 274: 범위 */
        WHERE r.is_rent = 0 AND r.is_canceled = 0 AND r.deal_amount IS NOT NULL
          AND r.match_pnu IS NOT NULL
          AND r.match_pnu >= k.하 AND r.match_pnu <= k.상
    ) r
) t;
GO
PRINT '274 완료';
