/* ③ 규칙 초안 근거(2026-11-19, 읽기만): 서울 실거래 종류별 분포 */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 종류 = trade_kind, 줄 = COUNT_BIG(*),
  금액없음 = SUM(CASE WHEN is_rent = 0 AND deal_amount IS NULL THEN 1 ELSE 0 END),
  금액0이하 = SUM(CASE WHEN is_rent = 0 AND deal_amount <= 0 THEN 1 ELSE 0 END),
  금액1천만미만 = SUM(CASE WHEN is_rent = 0 AND deal_amount > 0 AND deal_amount < 10000000 THEN 1 ELSE 0 END),
  금액500억초과 = SUM(CASE WHEN is_rent = 0 AND deal_amount > 50000000000 THEN 1 ELSE 0 END),
  금액최소 = MIN(CASE WHEN is_rent = 0 THEN deal_amount END), 금액최대 = MAX(CASE WHEN is_rent = 0 THEN deal_amount END),
  보증금없음 = SUM(CASE WHEN is_rent = 1 AND deposit IS NULL THEN 1 ELSE 0 END),
  보증금0월세0 = SUM(CASE WHEN is_rent = 1 AND ISNULL(deposit,0) = 0 AND ISNULL(monthly_rent,0) = 0 THEN 1 ELSE 0 END),
  보증금100억초과 = SUM(CASE WHEN is_rent = 1 AND deposit > 10000000000 THEN 1 ELSE 0 END),
  월세1천만초과 = SUM(CASE WHEN is_rent = 1 AND monthly_rent > 10000000 THEN 1 ELSE 0 END),
  면적없음 = SUM(CASE WHEN exclu_use_ar IS NULL THEN 1 ELSE 0 END),
  면적10미만 = SUM(CASE WHEN exclu_use_ar < 10 THEN 1 ELSE 0 END),
  면적300초과 = SUM(CASE WHEN exclu_use_ar > 300 THEN 1 ELSE 0 END),
  층없음 = SUM(CASE WHEN floor_no IS NULL THEN 1 ELSE 0 END),
  층음수 = SUM(CASE WHEN floor_no < 0 THEN 1 ELSE 0 END), 층0 = SUM(CASE WHEN floor_no = 0 THEN 1 ELSE 0 END),
  층70초과 = SUM(CASE WHEN floor_no > 70 THEN 1 ELSE 0 END), 층최소 = MIN(floor_no), 층최대 = MAX(floor_no),
  건축없음 = SUM(CASE WHEN build_year IS NULL THEN 1 ELSE 0 END),
  건축1900전 = SUM(CASE WHEN build_year < 1900 THEN 1 ELSE 0 END),
  건축이계약보다2년뒤 = SUM(CASE WHEN build_year > deal_year + 2 THEN 1 ELSE 0 END),
  계약일형식 = SUM(CASE WHEN deal_ymd IS NULL OR LEN(deal_ymd) <> 8 OR ISDATE(deal_ymd) = 0 THEN 1 ELSE 0 END),
  계약일미래 = SUM(CASE WHEN deal_ymd > CONVERT(CHAR(8), DATEADD(HOUR, 9, SYSDATETIME()), 112) THEN 1 ELSE 0 END),
  해제 = SUM(CAST(is_canceled AS INT)),
  직거래 = SUM(CASE WHEN dealing_gbn = N'직거래' THEN 1 ELSE 0 END),
  지번가림 = SUM(CAST(jibun_masked AS INT)),
  단지없음 = SUM(CASE WHEN match_complex_id IS NULL THEN 1 ELSE 0 END),
  최초 = MIN(deal_ymd), 최근 = MAX(deal_ymd)
FROM silver.rtms_trade GROUP BY trade_kind ORDER BY 2 DESC;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* 아파트 매매 ㎡당 가격(원/㎡) — 아주 싸거나 아주 비싼 것 */
SELECT ㎡당100만미만 = SUM(CASE WHEN deal_amount / exclu_use_ar < 1000000 THEN 1 ELSE 0 END),
       ㎡당300만미만 = SUM(CASE WHEN deal_amount / exclu_use_ar < 3000000 THEN 1 ELSE 0 END),
       ㎡당1억초과 = SUM(CASE WHEN deal_amount / exclu_use_ar > 100000000 THEN 1 ELSE 0 END),
       ㎡당2억초과 = SUM(CASE WHEN deal_amount / exclu_use_ar > 200000000 THEN 1 ELSE 0 END),
       ㎡당최소 = MIN(deal_amount / exclu_use_ar), ㎡당최대 = MAX(deal_amount / exclu_use_ar), 줄 = COUNT(*)
FROM silver.rtms_trade WHERE trade_kind = 'APT_TRADE_DEV' AND deal_amount > 0 AND exclu_use_ar > 0;
SELECT TOP 5 bld_nm, deal_ymd, deal_amount, exclu_use_ar, floor_no, dealing_gbn, cdeal_type, ㎡당 = deal_amount / exclu_use_ar
FROM silver.rtms_trade WHERE trade_kind = 'APT_TRADE_DEV' AND deal_amount > 0 AND exclu_use_ar > 0 ORDER BY deal_amount / exclu_use_ar ASC;
SELECT TOP 5 bld_nm, deal_ymd, deal_amount, exclu_use_ar, floor_no, dealing_gbn, cdeal_type, ㎡당 = deal_amount / exclu_use_ar
FROM silver.rtms_trade WHERE trade_kind = 'APT_TRADE_DEV' AND deal_amount > 0 AND exclu_use_ar > 0 ORDER BY deal_amount / exclu_use_ar DESC;
