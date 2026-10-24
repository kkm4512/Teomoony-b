SET NOCOUNT ON;
/* 340 원문 압축 — 범위 1 (병렬 줄 zp-gz1-par) */
EXEC bronze.usp_payload_compress @batch = 2000, @maxmin = 900, @from = 0, @to = 214000;
