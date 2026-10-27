/* 363 실거래 — 리 없이 온 읍·면 거래가 아무 리 코드에 붙었던 것 되돌리기 (2026-10-27 밤)
   load_rtms 의 이름→코드 표가 emd_nm 만 키로 써서, 리 행이 읍·면 이름을 덮어썼다('음봉면' → 음봉면 어느 리).
   umdNm 에 리가 없는데 match_pnu 의 리 자리(9~10번째)가 00 이 아닌 LAWD_JIBUN 거래 = 우리가 리를 고른 것 → 틀릴 수 있는 연결.
   ★ 원문 칸(umd_nm · jibun · 금액 …)은 손대지 않는다. 연결 칸(match_pnu · match_complex_id · match_method · match_note)만 되돌리고
     옛 값(match_pnu · 단지 · 방법)은 새 기록표 ops.rtms_unmatch_log 에 남긴다(ops.rtms_rematch_log 는 new_cid 가 NOT NULL 이라 '떼어냄' 을 못 적는다). 다음 load_rtms --rematch-only 가 고친 규칙으로 다시 본다(리 없으면 안 붙임). */
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF OBJECT_ID('tempdb..#w') IS NOT NULL DROP TABLE #w;
SELECT trade_sk, old_cid = match_complex_id INTO #w FROM silver.rtms_trade
 WHERE match_method = 'LAWD_JIBUN' AND umd_nm NOT LIKE N'% %' AND SUBSTRING(match_pnu, 9, 2) <> '00';
IF OBJECT_ID('ops.rtms_unmatch_log') IS NULL
    CREATE TABLE ops.rtms_unmatch_log (trade_sk BIGINT NOT NULL, old_pnu CHAR(19) NULL, old_cid INT NULL, old_method VARCHAR(20) NULL,
                                       why NVARCHAR(100) NOT NULL, at DATETIME2(0) NOT NULL DEFAULT SYSDATETIME());
BEGIN TRAN;
INSERT INTO ops.rtms_unmatch_log (trade_sk, old_pnu, old_cid, old_method, why)
SELECT t.trade_sk, t.match_pnu, t.match_complex_id, t.match_method, N'363 리 없이 온 읍·면' FROM silver.rtms_trade t JOIN #w w ON w.trade_sk = t.trade_sk;
UPDATE t SET match_pnu = NULL, match_complex_id = NULL, match_method = 'NO_LAWD', match_note = N'363: 리 없이 온 읍·면 — 어느 리인지 모름'
  FROM silver.rtms_trade t JOIN #w w ON w.trade_sk = t.trade_sk;
COMMIT;
SELECT 되돌림 = (SELECT COUNT(*) FROM #w), 단지연결있던것 = (SELECT COUNT(*) FROM #w WHERE old_cid IS NOT NULL);
GO
