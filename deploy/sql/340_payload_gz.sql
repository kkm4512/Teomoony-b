/* 나눠 돌리기: @from < payload_id <= @to 범위마다 따로(340_payload_gz_run1..4 — 병렬 줄)
   2026-10-24 전국 넓히기 전 진단 ① — 원문 보관 표(bronze.api_payload)가 DB 185GB 중 **129GB**.
   서울·안양만으로 이만큼이고 전국(건물 약 12배)이면 1.5TB — 남은 디스크(755GB)를 넘는다.
   ★ 원문은 **지우지 않는다**(원본 훼손 금지). gzip(COMPRESS) 으로 같은 줄에 담고, **풀어서 원문과 한 글자도 다르지 않을 때만** 평문 칸을 비운다.
     표본 550건: 25~50배 줄고 550/550 같음(BIN2 비교). 되돌리기 = CAST(DECOMPRESS(body_gz) AS NVARCHAR(MAX)).
   ★ 읽는 쪽은 bronze.v_api_payload 의 body 를 본다(평문이든 압축이든 같은 글). 적재기는 이제 body_gz 로만 쓴다(teomoony_ingest). */
IF COL_LENGTH('bronze.api_payload', 'body_gz') IS NULL
    ALTER TABLE bronze.api_payload ADD body_gz VARBINARY(MAX) NULL;
GO
CREATE OR ALTER VIEW bronze.v_api_payload AS
SELECT payload_id, run_id, source_id, req_url_hash, req_params, http_status, result_code,
       body = COALESCE(body, CAST(DECOMPRESS(body_gz) AS NVARCHAR(MAX))), body_sha256, fetched_at,
       압축 = CASE WHEN body IS NULL AND body_gz IS NOT NULL THEN 1 ELSE 0 END
  FROM bronze.api_payload;
GO
CREATE OR ALTER PROCEDURE bronze.usp_payload_compress @batch INT = 2000, @maxmin INT = 600, @from BIGINT = 0, @to BIGINT = 9223372036854775807
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @t0 DATETIME2 = SYSDATETIME(), @n INT = 1, @done BIGINT = 0, @lo BIGINT = @from, @hi BIGINT, @틀림 INT = 0, @m INT;
    WHILE @n > 0 AND DATEDIFF(MINUTE, @t0, SYSDATETIME()) < @maxmin
    BEGIN
        /* payload_id 순서대로 한 묶음 — 클러스터 키라 범위로 집는다 */
        SELECT @hi = MAX(payload_id) FROM (SELECT TOP (@batch) payload_id FROM bronze.api_payload
                                             WHERE payload_id > @lo AND payload_id <= @to AND body IS NOT NULL ORDER BY payload_id) x;
        IF @hi IS NULL BREAK;
        BEGIN TRAN;
          UPDATE bronze.api_payload SET body_gz = COMPRESS(body)
           WHERE payload_id > @lo AND payload_id <= @hi AND body IS NOT NULL AND body_gz IS NULL;
          /* 풀어서 **똑같을 때만** 평문을 비운다 */
          UPDATE bronze.api_payload SET body = NULL
           WHERE payload_id > @lo AND payload_id <= @hi AND body IS NOT NULL AND body_gz IS NOT NULL
             AND CAST(DECOMPRESS(body_gz) AS NVARCHAR(MAX)) = body COLLATE Latin1_General_BIN2;
          SET @n = @@ROWCOUNT;
          SELECT @m = COUNT(*) FROM bronze.api_payload WHERE payload_id > @lo AND payload_id <= @hi AND body IS NOT NULL;
        COMMIT;
        SET @틀림 += @m; SET @done += @n; SET @lo = @hi; SET @n = 1;
        IF @done % 50000 < @batch
            RAISERROR('  %I64d 줄 · 마지막 id %I64d · 풀어 다른 것 %d', 0, 1, @done, @hi, @틀림) WITH NOWAIT;
    END
    SELECT 압축한줄 = @done, 풀어다른것 = @틀림, 분 = DATEDIFF(MINUTE, @t0, SYSDATETIME()),
           남은평문 = (SELECT COUNT_BIG(*) FROM bronze.api_payload WHERE payload_id > @from AND payload_id <= @to AND body IS NOT NULL);
END
GO
