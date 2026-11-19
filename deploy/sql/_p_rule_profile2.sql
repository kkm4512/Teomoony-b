SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* 아파트 매매 m2당 가격(원/㎡) — 아주 싸거나 아주 비싼 것 */
SELECT m2당100만미만 = SUM(CASE WHEN deal_amount / exclu_use_ar < 1000000 THEN 1 ELSE 0 END),
       m2당300만미만 = SUM(CASE WHEN deal_amount / exclu_use_ar < 3000000 THEN 1 ELSE 0 END),
       m2당1억초과 = SUM(CASE WHEN deal_amount / exclu_use_ar > 100000000 THEN 1 ELSE 0 END),
       m2당2억초과 = SUM(CASE WHEN deal_amount / exclu_use_ar > 200000000 THEN 1 ELSE 0 END),
       m2당최소 = MIN(deal_amount / exclu_use_ar), m2당최대 = MAX(deal_amount / exclu_use_ar), 줄 = COUNT(*)
FROM silver.rtms_trade WHERE trade_kind = 'APT_TRADE_DEV' AND deal_amount > 0 AND exclu_use_ar > 0;
SELECT TOP 5 bld_nm, deal_ymd, deal_amount, exclu_use_ar, floor_no, dealing_gbn, cdeal_type, m2당 = deal_amount / exclu_use_ar
FROM silver.rtms_trade WHERE trade_kind = 'APT_TRADE_DEV' AND deal_amount > 0 AND exclu_use_ar > 0 ORDER BY deal_amount / exclu_use_ar ASC;
SELECT TOP 5 bld_nm, deal_ymd, deal_amount, exclu_use_ar, floor_no, dealing_gbn, cdeal_type, m2당 = deal_amount / exclu_use_ar
FROM silver.rtms_trade WHERE trade_kind = 'APT_TRADE_DEV' AND deal_amount > 0 AND exclu_use_ar > 0 ORDER BY deal_amount / exclu_use_ar DESC;
