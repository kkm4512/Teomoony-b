SET NOCOUNT ON;
/* 340 원문 압축 — 범위 4 (병렬 줄 zp-gz4-par) */
EXEC bronze.usp_payload_compress @batch = 2000, @maxmin = 900, @from = 642000, @to = 9223372036854775807;
