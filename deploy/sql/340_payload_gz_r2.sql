SET NOCOUNT ON;
/* 340 원문 압축 — 범위 2 (병렬 줄 zp-gz2-par) */
EXEC bronze.usp_payload_compress @batch = 2000, @maxmin = 900, @from = 214000, @to = 428000;
