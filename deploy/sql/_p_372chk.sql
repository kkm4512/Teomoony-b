SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 옮김 = (SELECT COUNT(*) FROM ops.rtms_rematch_log WHERE run_id = 11),
       뗌 = (SELECT COUNT(*) FROM ops.rtms_unmatch_log WHERE why LIKE N'372%'),
       노트 = (SELECT COUNT(*) FROM silver.rtms_trade WHERE match_note LIKE N'372:%'),
       노트인데붙음 = (SELECT COUNT(*) FROM silver.rtms_trade WHERE match_note LIKE N'372:%' AND match_complex_id IS NOT NULL);
SELECT complex_id, complex_nm, trade_cnt, rent_cnt FROM gold.complex WHERE complex_id IN (548190, 545619, 120369, 120622, 120647);
