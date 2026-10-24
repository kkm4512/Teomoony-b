SET NOCOUNT ON;
/* 340 원문 압축 — 범위 3 (병렬 줄 zp-gz3-par) */
EXEC bronze.usp_payload_compress @batch = 2000, @maxmin = 900, @from = 428000, @to = 642000;
