/* 273. 법정동 지도(/api/lawds) 48~94초 → 덮는 색인 + 뷰 손질 (2026-10-21, 사장님 승인 15:18)
   ★ 왜 (CONTEXT 11-120)
     gold.v_lawd_map 의 실거래 OUTER APPLY 가 법정동 하나당 1.4~1.9초.
     색인 탐색(ix_rtms_pnu)은 124ms 로 빠른데, 거름칸(is_rent·is_canceled·deal_amount)과
     뽑는 칸(deal_ymd·면적)을 보려고 **행마다 본문으로 되돌아가는 키 조회**가 느렸다.
     실측 기준(15:20): 좁은 bbox 17,791ms · 성북구 bbox 93,859ms.
   ★ 무엇
     ① **거른 덮는 색인** — 매매 · 금액 있음 · PNU 있음만 담는다(해제는 계산 칸이라 INCLUDE 로).
        1,060만 중 251만(24%)이라 ix_rtms_pnu 에 INCLUDE 를 붙이는 것보다 작다.
        ix_rtms_pnu 는 다른 질의가 쓰므로 **건드리지 않는다.**
     ② 뷰: LEFT(match_pnu,10) = lawd_cd → match_pnu LIKE lawd_cd + '%' (색인 범위탐색이 되게)
        + 색인 거름과 똑같은 match_pnu IS NOT NULL 을 적는다(옵티마이저가 거른 색인을 고르게).
        11-120 에서 '범위로 바꾸기만으로는 안 낫는다' 고 적었다 — 그건 키 조회가 병목일 때다.
        이제 키 조회가 없어지므로 범위탐색이 의미가 생긴다.
     ③ 덤: max_area 에 building_ar 을 더한다 — COALESCE(exclu_use_ar, total_floor_ar, building_ar).
        11-105 와 **네 번째** 같은 자리(상세 실거래 카드는 이미 이 순서다 · server.js 3454).
   ★ rtms_trade 는 지금 아무도 안 쓴다(적재는 bld_hsprc · 학원). 만드는 동안 이 표를 읽는 화면이
     잠깐 막힐 수 있다. MAXDOP 4 · SORT_IN_TEMPDB.
   ★ 다시 돌려도 된다. 지우는 문장 없음.
   ★ 되돌리기: DROP INDEX ix_rtms_lawd_trade ON silver.rtms_trade; + 10_lawd_boundary.sql 의 뷰 */
SET NOCOUNT ON;
GO
DECLARE @t DATETIME2 = SYSDATETIME();
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_rtms_lawd_trade'
                AND object_id = OBJECT_ID('silver.rtms_trade'))
    CREATE INDEX ix_rtms_lawd_trade
        ON silver.rtms_trade (match_pnu)
        INCLUDE (deal_amount, deal_ymd, exclu_use_ar, total_floor_ar, building_ar, is_canceled)
        /* ⚠ is_canceled 는 계산 칸(cdeal_type = 'O')이라 거름에 못 쓴다(오류 10609, 15:24 겪음).
           그래서 거름에서 빼고 INCLUDE 로 담는다 - 해제는 적어서 색인 크기는 거의 같다.
           뷰의 is_canceled = 0 은 색인 안에서 걸러진다(본문으로 안 돌아간다). */
        WHERE is_rent = 0 AND deal_amount IS NOT NULL AND match_pnu IS NOT NULL
        WITH (MAXDOP = 4, SORT_IN_TEMPDB = ON);
PRINT CONCAT('ix_rtms_lawd_trade (초) = ', DATEDIFF(SECOND, @t, SYSDATETIME()));
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
OUTER APPLY (
    SELECT COUNT(*) AS complex_cnt,
           SUM(c.dong_cnt) AS dong_cnt,
           SUM(c.hhld_cnt_sum) AS hhld_cnt
    FROM gold.complex c
    WHERE LEFT(c.rep_pnu, 10) = b.lawd_cd
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
        /* 273: ix_rtms_lawd_trade 의 거름과 **똑같이** 적는다 + 앞자리 범위탐색 */
        WHERE r.is_rent = 0 AND r.is_canceled = 0 AND r.deal_amount IS NOT NULL
          AND r.match_pnu IS NOT NULL
          AND r.match_pnu LIKE CAST(b.lawd_cd AS VARCHAR(10)) + '%'
    ) r
) t;
GO
PRINT '273 완료';
