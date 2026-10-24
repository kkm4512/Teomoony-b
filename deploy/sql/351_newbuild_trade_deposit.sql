/* 351 gold.v_newbuild_trade — 전월세 '최고' 가 비던 것 (2026-10-24 21:46 사장님 "전월세는 왜 보증금이 없어?")
   ★ 매매가(deal_amount) 만 모았다 — 전월세는 deal_amount 가 비고 보증금이 deposit 에 있다. 전월세 줄은 **보증금** 으로.
   ★ 292 의 '분양권 제외' 가 이 뷰에는 안 들어가 있었다(실측: 정의에 SILV 없음) — 같이 넣는다.
   ★ 원래 칸 이름(min/max_amount)은 그대로 둔다(쓰는 곳 4곳: 단지 밖 거래 · 신축 마커 등). 매매 = 매매가, 전월세 = 보증금. */
CREATE OR ALTER VIEW gold.v_newbuild_trade
AS
SELECT pnu          = r.match_pnu,
       apt_seq      = r.apt_seq,
       seq_nm       = MIN(r.bld_nm),
       is_rent      = r.is_rent,
       area_grp     = CAST(FLOOR(COALESCE(r.exclu_use_ar, r.total_floor_ar, r.building_ar)) AS INT),
       cnt          = SUM(CASE WHEN r.is_canceled = 0 THEN 1 ELSE 0 END),
       canceled_cnt = SUM(CAST(r.is_canceled AS INT)),
       min_amount   = MIN(CASE WHEN r.is_canceled = 0 THEN CASE WHEN r.is_rent = 1 THEN r.deposit ELSE r.deal_amount END END),
       max_amount   = MAX(CASE WHEN r.is_canceled = 0 THEN CASE WHEN r.is_rent = 1 THEN r.deposit ELSE r.deal_amount END END),
       last_ymd     = MAX(CASE WHEN r.is_canceled = 0 THEN r.deal_ymd END),
       direct_cnt   = SUM(CASE WHEN r.is_canceled = 0 AND r.dealing_gbn LIKE N'%직거래%' THEN 1 ELSE 0 END)
FROM silver.rtms_trade r
WHERE r.match_pnu IS NOT NULL
  AND r.match_complex_id IS NULL
  AND r.trade_kind NOT LIKE 'SILV%'   /* 292 분양권 제외(292 가 이 뷰에는 못 끼웠다 — 끼울 자리 줄바꿈이 달라 @n<>1. 여기서 같이) */
  AND COALESCE(r.exclu_use_ar, r.total_floor_ar, r.building_ar) IS NOT NULL
GROUP BY r.match_pnu, r.apt_seq, r.is_rent,
         CAST(FLOOR(COALESCE(r.exclu_use_ar, r.total_floor_ar, r.building_ar)) AS INT);
GO
