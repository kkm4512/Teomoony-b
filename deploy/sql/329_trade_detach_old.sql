/* ============================================================
   329_trade_detach_old : 헐린 **옛 건물**의 실거래가 그 자리 **새 건물**에 붙은 것을 뗀다 (2026-10-23 사장님 "ㄱㄱ")
   ★ 왜(AI 검색 QA 100문항에서 드러남): 282 필지 매칭은 지번만 보고 날짜를 안 본다 — 재건축·신축으로 같은 지번에 새 건물이 서면 옛 거래가 새 건물에 붙는다.
       신반포스포츠센터(2025-12 · 세대 0) ← 신반포9·10·17 · 녹원한신 3,366건 · 원베일리 스퀘어 ← 한신3차 1,314 · 포레나노원 ← 상계주공8(저층) 1,536 …
   ★ 규칙(이름은 안 본다 · 둘 중 하나):
       ① 세대 0 단지(체육관 · 상가 · 근생)에 붙은 **주거 거래**(아파트 · 연립 · 단독) 중 그 단지 사용승인 **전** 계약
       ② 세대 단지에 붙은 아파트 거래 중 같은 아파트 번호(aptSeq · 같은 지번)의 **마지막 계약이 사용승인 전**이고 **첫 계약이 사용승인 3년 전보다 이른** 것
          (새 단지의 분양 계약은 준공 몇 해 전부터 신고되지만 준공 뒤에도 같은 번호로 이어진다 — 옛 건물 번호는 준공 전에 끝난다)
   ★ 원본 칸(match_pnu 등)은 그대로 · match_complex_id 만 비운다 → 그 지번의 폐쇄 대장 상세에 옛 거래로 보인다.
     떼어낸 것은 ops.rtms_detach_log 에(되돌리기: UPDATE t SET match_complex_id = l.old_cid FROM silver.rtms_trade t JOIN ops.rtms_detach_log l ON l.trade_sk = t.trade_sk WHERE l.run_id = n).
   ★ 318 프로시저 끝에서 부른다(282 → 318 → 328 → 329) — 적재 때마다 다시 붙어도 다시 뗀다. 로그는 처음 뗄 때만.
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
IF OBJECT_ID('ops.rtms_detach_log') IS NULL
CREATE TABLE ops.rtms_detach_log (
    run_id    INT          NOT NULL,
    trade_sk  BIGINT       NOT NULL,
    old_cid   INT          NOT NULL,
    근거      NVARCHAR(40) NOT NULL,
    at        DATETIME2(0) NOT NULL CONSTRAINT df_rtms_detach_log_at DEFAULT SYSDATETIME(),
    CONSTRAINT pk_rtms_detach_log PRIMARY KEY CLUSTERED (run_id, trade_sk)
);
GO
CREATE OR ALTER PROCEDURE gold.usp_detach_old_building_trades
    @dry BIT = 0, @n INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @run INT = ISNULL((SELECT MAX(run_id) FROM ops.rtms_detach_log), 0) + 1;
    IF OBJECT_ID('tempdb..#d') IS NOT NULL DROP TABLE #d;
    /* ① 세대 0 단지 · 주거 거래 · 사용승인 전 */
    SELECT t.trade_sk, cid = t.match_complex_id, 근거 = CAST(N'세대 0 건물 · 사용승인 전 주거 거래' AS NVARCHAR(40))
      INTO #d
      FROM silver.rtms_trade t JOIN gold.complex c ON c.complex_id = t.match_complex_id
     WHERE ISNULL(c.hhld_cnt_sum, 0) = 0 AND LEN(c.oldest_use_apr) = 8 AND t.deal_ymd < c.oldest_use_apr
       AND (t.trade_kind LIKE 'APT%' OR t.trade_kind LIKE 'RH%' OR t.trade_kind LIKE 'SH%');
    /* ② 세대 단지 · 아파트 · 옛 아파트 번호 */
    IF OBJECT_ID('tempdb..#g') IS NOT NULL DROP TABLE #g;
    SELECT t.match_complex_id cid, t.apt_seq, t.match_pnu, 처음 = MIN(t.deal_ymd), 끝 = MAX(t.deal_ymd)
      INTO #g FROM silver.rtms_trade t
     WHERE t.match_complex_id IS NOT NULL AND t.apt_seq IS NOT NULL AND t.trade_kind LIKE 'APT%'
     GROUP BY t.match_complex_id, t.apt_seq, t.match_pnu;
    INSERT INTO #d (trade_sk, cid, 근거)
    SELECT t.trade_sk, t.match_complex_id, N'옛 아파트 번호 · 사용승인 전에 끝남'
      FROM #g g JOIN gold.complex c ON c.complex_id = g.cid
      JOIN silver.rtms_trade t ON t.match_complex_id = g.cid AND t.apt_seq = g.apt_seq AND t.match_pnu = g.match_pnu AND t.trade_kind LIKE 'APT%'
     WHERE c.hhld_cnt_sum > 0 AND LEN(c.oldest_use_apr) = 8
       AND g.끝 < c.oldest_use_apr
       AND g.처음 < CONVERT(CHAR(8), DATEADD(YEAR, -3, TRY_CONVERT(DATE, c.oldest_use_apr)), 112)
       AND NOT EXISTS (SELECT 1 FROM #d d WHERE d.trade_sk = t.trade_sk);
    SET @n = (SELECT COUNT(*) FROM #d);
    IF @dry = 1
    BEGIN
        SELECT r = (SELECT 뗄 = @n, 근거별 = (SELECT 근거, n = COUNT(*), 단지 = COUNT(DISTINCT cid) FROM #d GROUP BY 근거 FOR JSON PATH),
                    예 = (SELECT TOP 25 c.complex_nm, c.oldest_use_apr, c.hhld_cnt_sum, d.근거, n = COUNT(*), 이름 = MAX(t.bld_nm), 처음 = MIN(t.deal_ymd), 끝 = MAX(t.deal_ymd)
                           FROM #d d JOIN gold.complex c ON c.complex_id = d.cid JOIN silver.rtms_trade t ON t.trade_sk = d.trade_sk
                          GROUP BY c.complex_nm, c.oldest_use_apr, c.hhld_cnt_sum, d.근거 ORDER BY COUNT(*) DESC FOR JSON PATH)
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        RETURN;
    END
    IF @n > 0
    BEGIN
        BEGIN TRAN;
            INSERT INTO ops.rtms_detach_log (run_id, trade_sk, old_cid, 근거)
            SELECT @run, d.trade_sk, d.cid, d.근거 FROM #d d
             WHERE NOT EXISTS (SELECT 1 FROM ops.rtms_detach_log l WHERE l.trade_sk = d.trade_sk AND l.old_cid = d.cid);
            UPDATE t SET t.match_complex_id = NULL FROM silver.rtms_trade t JOIN #d d ON d.trade_sk = t.trade_sk AND t.match_complex_id = d.cid;
        COMMIT;
    END
END
GO
EXEC gold.usp_detach_old_building_trades @dry = 1;
