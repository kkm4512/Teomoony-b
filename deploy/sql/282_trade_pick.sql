/* ============================================================
   282_trade_pick : 실거래를 단지에 붙일 때 **한 필지에 단지가 여럿이면 누구에게** (2026-10-21)

   ★ 문제 (실측)
     load_rtms.py 의 단지 매칭이
         UPDATE t SET match_complex_id = cp.complex_id
           FROM silver.rtms_trade t JOIN gold.complex_pnu cp ON cp.pnu = t.match_pnu
     였다. **한 PNU 에 단지가 둘 이상이면 SQL Server 는 그중 아무거나 하나를 쓴다.**
     아파트와 같은 필지에 어린이집·유치원·상가가 따로 대장 root 를 갖고 있으면
     (=따로 단지로 잡히면) 아파트 거래가 그쪽으로 간다.
       잠실어린이집(세대 0) 5,195건 ← 실제는 파크리오 · 노원 월계동 '유치원' 3,795건 …
       단지가 여럿인 필지 10,790 · 그중 세대 있는 단지가 둘 이상 441
       세대 0 단지에 붙었는데 같은 필지에 세대 있는 단지가 있던 거래
         APT 매매 81,516 · APT 전월세 163,411 · 연립 4,933 + 6,706 · 오피스텔 1,995 + 1,561
     **숫자는 다 있고 단지만 틀려서** 집계로는 안 드러났다(큰 단지의 건수가 덜 보였다).

   ★ 규칙 (한 자리 — 이 프로시저)
     거래 종류마다 '이 거래를 담을 수 있는 건물' 을 먼저 본다. 이름은 안 쓴다(정책 1장).
       주거(APT_* · RH_* · SH_*)  **주택 동** 세대 있는 단지 > 그 세대 많은 > 대지(MAIN) > 연면적 큰 > 코드 작은
       오피스텔(OFFI_*)            오피스텔 용도 동이 있는 단지 > 대지 > 연면적 큰 > 코드 작은
       그 밖(NRG · LAND)            대지 > 연면적 큰 > 코드 작은
     ⚠ 세대 있는 단지가 둘 이상인 필지(441)는 **큰 쪽**으로 간다 — 구조로 가를 근거가 없다.
       예전엔 아무거나였으니 나빠지지는 않는다. 화면이 '같은 필지 다른 단지' 를 말할지는 다음 일.

   ★ 원본을 지우지 않는다 — 바꾼 거래는 ops.rtms_rematch_log 에 옛 값과 함께 남는다.
     되돌리기: UPDATE t SET match_complex_id = l.old_cid FROM silver.rtms_trade t
               JOIN ops.rtms_rematch_log l ON l.trade_sk = t.trade_sk AND l.run_id = <회차>;
   ★ 나눠서 바꾼다(2만 건씩) — 적재가 같은 표를 쓰고 있어도 오래 막지 않게.
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
IF OBJECT_ID('ops.rtms_rematch_log') IS NULL
CREATE TABLE ops.rtms_rematch_log (
    run_id    INT          NOT NULL,
    trade_sk  BIGINT       NOT NULL,
    old_cid   INT          NULL,
    new_cid   INT          NOT NULL,
    at        DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_rtms_rematch_log PRIMARY KEY CLUSTERED (run_id, trade_sk)
);
GO
CREATE OR ALTER PROCEDURE gold.usp_match_complex_trade
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @t0 DATETIME2 = SYSDATETIME();
    DECLARE @run INT = ISNULL((SELECT MAX(run_id) FROM ops.rtms_rematch_log), 0) + 1;

    /* 단지마다 성질 — 세대 · 연면적 · 오피스텔 동이 있나 */
    IF OBJECT_ID('tempdb..#c') IS NOT NULL DROP TABLE #c;
    /* ★ 18:05: '세대' 는 **주용도가 주택인 동**의 세대만 센다. 대장 세대수 칸이 상가·시장에도 차 있다
       (잠실파인애플상가 근린 489 · 동대문종합시장 판매 1,089 · 로담코인사빌딩 숙박 213). */
    SELECT c.complex_id,
           hhld = ISNULL((SELECT SUM(ISNULL(tt.hhld_cnt, 0)) FROM gold.complex_bld cb
                            JOIN silver.bld_title tt ON tt.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND tt.is_current = 1
                           WHERE cb.complex_id = c.complex_id AND tt.main_purps_nm LIKE N'%주택%'), 0),
           area = ISNULL(c.tot_area_sum, 0),
           offi = CASE WHEN EXISTS (SELECT 1 FROM gold.complex_bld cb
                                      JOIN silver.bld_title tt ON tt.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND tt.is_current = 1
                                     WHERE cb.complex_id = c.complex_id
                                       AND (tt.main_purps_nm LIKE N'%오피스텔%' OR tt.etc_purps LIKE N'%오피스텔%'))
                       THEN 1 ELSE 0 END
      INTO #c
      FROM gold.complex c
     WHERE c.complex_id IN (SELECT cp.complex_id FROM gold.complex_pnu cp
                             WHERE cp.pnu IN (SELECT pnu FROM gold.complex_pnu GROUP BY pnu HAVING COUNT(*) > 1));
    CREATE CLUSTERED INDEX x ON #c (complex_id);

    /* 필지 × 종류군 → 고른 단지. 단지가 하나인 필지는 그 단지. */
    IF OBJECT_ID('tempdb..#p') IS NOT NULL DROP TABLE #p;
    SELECT pnu, grp, complex_id INTO #p FROM (
        SELECT cp.pnu, g.grp, cp.complex_id,
               rn = ROW_NUMBER() OVER (PARTITION BY cp.pnu, g.grp ORDER BY
                      CASE WHEN g.grp = 'R' AND ISNULL(x.hhld, 1) > 0 THEN 0
                           WHEN g.grp = 'O' AND ISNULL(x.offi, 1) = 1 THEN 0
                           WHEN g.grp = 'X' THEN 0 ELSE 1 END,
                      /* ★ 17:57 사장님과 정함: 주거는 **세대 많은 조각**이 대지보다 먼저 —
                         한 단지가 대장 여러 개로 쪼개진 곳(중계그린 878 MAIN + 1,675 ATTACHED)에서 큰 쪽에 붙게.
                         쪼개진 조각을 하나로 묶는 일은 따로(286, 결과 먼저 보고). */
                      CASE WHEN g.grp = 'R' THEN ISNULL(x.hhld, 0) ELSE 0 END DESC,
                      CASE WHEN cp.pnu_role = 'MAIN' THEN 0 ELSE 1 END,
                      ISNULL(x.area, 0) DESC,
                      cp.complex_id)
          FROM gold.complex_pnu cp
          CROSS JOIN (VALUES ('R'), ('O'), ('X')) g(grp)
          LEFT JOIN #c x ON x.complex_id = cp.complex_id) z
     WHERE rn = 1;
    CREATE CLUSTERED INDEX x ON #p (pnu, grp);

    /* 바꿀 거래를 먼저 뽑는다 */
    IF OBJECT_ID('tempdb..#f') IS NOT NULL DROP TABLE #f;
    SELECT t.trade_sk, old_cid = t.match_complex_id, new_cid = p.complex_id
      INTO #f
      FROM silver.rtms_trade t
      JOIN #p p ON p.pnu = t.match_pnu
               AND p.grp = CASE WHEN t.trade_kind LIKE 'APT%' OR t.trade_kind LIKE 'RH%' OR t.trade_kind LIKE 'SH%' THEN 'R'
                                WHEN t.trade_kind LIKE 'OFFI%' THEN 'O' ELSE 'X' END
     WHERE t.match_pnu IS NOT NULL
       AND t.trade_kind NOT LIKE 'SILV%'   -- ★ 2026-10-21: 분양권·입주권은 **사업 전 지번**이라 철거 전 옛 단지에 붙으면 틀린다 — 안 붙인다(291)
       AND (t.match_complex_id IS NULL OR t.match_complex_id <> p.complex_id);
    CREATE CLUSTERED INDEX x ON #f (trade_sk);
    DECLARE @n INT = (SELECT COUNT(*) FROM #f),
            @새로 INT = (SELECT COUNT(*) FROM #f WHERE old_cid IS NULL);

    /* 2만 건씩 — 기록 먼저, 그다음 바꾼다(같은 트랜잭션) */
    DECLARE @lo BIGINT = 0, @hi BIGINT;
    WHILE 1 = 1
    BEGIN
        SELECT @hi = MAX(trade_sk) FROM (SELECT TOP (20000) trade_sk FROM #f WHERE trade_sk > @lo ORDER BY trade_sk) s;
        IF @hi IS NULL BREAK;
        BEGIN TRAN;
            INSERT INTO ops.rtms_rematch_log (run_id, trade_sk, old_cid, new_cid)
            SELECT @run, trade_sk, old_cid, new_cid FROM #f WHERE trade_sk > @lo AND trade_sk <= @hi AND old_cid IS NOT NULL;
            UPDATE t SET t.match_complex_id = f.new_cid
              FROM silver.rtms_trade t JOIN #f f ON f.trade_sk = t.trade_sk
             WHERE f.trade_sk > @lo AND f.trade_sk <= @hi;
        COMMIT;
        SET @lo = @hi;
    END

    /* 318 (2026-10-23): 필지로 못 붙은 아파트 거래 → K-apt 지번(사업 전 지번)으로. 결과 행을 안 내보낸다 — 아래 한 행만 나간다(load_rtms.py) */
    DECLARE @kapt INT = 0;
    IF OBJECT_ID('gold.usp_match_trade_kapt') IS NOT NULL EXEC gold.usp_match_trade_kapt @dry = 0, @n = @kapt OUTPUT;

    SELECT 회차 = @run, 바꿈 = @n - @새로, 새로붙음 = @새로,
           여럿필지단지 = (SELECT COUNT(*) FROM #c), 초 = DATEDIFF(SECOND, @t0, SYSDATETIME()), K_apt지번 = @kapt;
END
GO
