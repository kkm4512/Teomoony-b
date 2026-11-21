/* ============================================================
   425_trade_aptseq : 단지에 안 붙은 실거래 → **같은 국토부 단지번호(aptSeq)를 이어받아** 그 단지에 (2026-11-21 사장님 "그렇게하고")
   ★ 왜(DQM '단지로 찾기' · 경희궁자이 37903): 준공 무렵 거래가 **법정동 코드가 다른 같은 본번**(교남동 쪽 199 ↔ 단지 필지 179-199 등)으로
     신고돼 필지 매칭(282)도 K-apt 지번(318)도 못 만났다. 그런데 같은 aptSeq(11110-2445)의 2019 년 이후 거래는 이미 37903 에 붙어 있다.
     aptSeq 는 국토부가 단지마다 매기는 번호 — 같은 번호의 뒤 거래가 한 단지에 붙어 있으면 앞 거래도 그 단지다.
   ★ 규칙(이름은 안 본다 · 모두 맞아야):
       ① 아파트 · 연립 · 오피스텔 거래 · 분양권·입주권 아님(291) · 아직 단지 없음
       ② 그 aptSeq 의 이미 붙은 거래가 **단지 하나**에만 · 20줄 이상 · 그 aptSeq 전체의 **절반 이상** —
          (반포주공1단지 2,658줄 중 1줄만 901번지 30세대 건물에 붙은 것 같은 '우연히 하나 붙은' 번호를 막는다)
       ③ 그 aptSeq 의 첫 계약이 단지 사용승인 3년 전 이후 · 마지막 계약이 사용승인 뒤(옛 건물 번호는 승인 전에 끝난다 — 318 과 같은 생각)
       ④ 거래 원문의 건축년도가 있으면 단지 사용승인 연도 ±1 안
       ⑤ 그 거래 필지가 어느 단지 필지도 아니다(282 · 372 가 맡는 곳은 건드리지 않는다) · 329 가 뗀 줄 · 372 가 뗀 줄(unmatch_log)은 안 붙인다
   ★ 원본 칸(match_pnu · match_method)은 안 바꾼다. 붙인 것은 ops.rtms_rematch_log 에 (old_cid NULL) — 되돌리기는 282 와 같다.
   ★ load_rtms.match_pass 에서 usp_match_complex_trade 다음에 부른다(적재 끝마다).
   EXEC gold.usp_match_trade_aptseq @dry = 1 → 결과만 보기.
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE gold.usp_match_trade_aptseq
    @dry BIT = 0, @n INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @run INT = ISNULL((SELECT MAX(run_id) FROM ops.rtms_rematch_log), 0) + 1;
    IF OBJECT_ID('tempdb..#s') IS NOT NULL DROP TABLE #s;
    SELECT g.apt_seq, g.cid, g.붙음, g.전체, g.처음, g.끝, 준공 = c.oldest_use_apr, 준공끝 = ISNULL(c.latest_use_apr, c.oldest_use_apr)
      INTO #s
      FROM (SELECT apt_seq, cid = MIN(match_complex_id), 붙음 = COUNT(match_complex_id), 전체 = COUNT(*), 처음 = MIN(deal_ymd), 끝 = MAX(deal_ymd)
              FROM silver.rtms_trade WITH (NOLOCK)
             WHERE apt_seq IS NOT NULL AND trade_kind NOT LIKE 'SILV%'
             GROUP BY apt_seq
            HAVING COUNT(DISTINCT match_complex_id) = 1 AND COUNT(match_complex_id) >= 20 AND COUNT(match_complex_id) * 2 >= COUNT(*)
               AND COUNT(match_complex_id) < COUNT(*)) g
      JOIN gold.complex c ON c.complex_id = g.cid AND c.is_active = 1 AND c.merged_into IS NULL AND c.hhld_cnt_sum > 0 AND LEN(c.oldest_use_apr) = 8
     WHERE g.처음 >= CONVERT(CHAR(8), DATEADD(YEAR, -3, TRY_CONVERT(DATE, c.oldest_use_apr)), 112)
       AND g.끝 >= c.oldest_use_apr;
    CREATE CLUSTERED INDEX x ON #s (apt_seq);
    IF OBJECT_ID('tempdb..#f') IS NOT NULL DROP TABLE #f;
    SELECT t.trade_sk, s.cid
      INTO #f
      FROM silver.rtms_trade t JOIN #s s ON s.apt_seq = t.apt_seq
     WHERE t.match_complex_id IS NULL AND t.trade_kind NOT LIKE 'SILV%'
       AND (t.trade_kind LIKE 'APT%' OR t.trade_kind LIKE 'RH%' OR t.trade_kind LIKE 'OFFI%')
       AND (TRY_CAST(t.build_year AS INT) IS NULL
            OR TRY_CAST(t.build_year AS INT) BETWEEN TRY_CAST(LEFT(s.준공, 4) AS INT) - 1 AND TRY_CAST(LEFT(s.준공끝, 4) AS INT) + 1)
       AND NOT EXISTS (SELECT 1 FROM gold.complex_pnu cp WHERE cp.pnu = t.match_pnu)
       AND NOT EXISTS (SELECT 1 FROM ops.rtms_detach_log l WHERE l.trade_sk = t.trade_sk)
       AND NOT EXISTS (SELECT 1 FROM ops.rtms_unmatch_log u WHERE u.trade_sk = t.trade_sk);
    SET @n = (SELECT COUNT(*) FROM #f);
    IF @dry = 1
    BEGIN
        SELECT 붙일거래 = @n, 단지 = (SELECT COUNT(DISTINCT cid) FROM #f), 후보aptSeq = (SELECT COUNT(*) FROM #s);
        SELECT TOP 30 f.cid, c.complex_nm, 사용승인 = LEFT(c.oldest_use_apr, 4), 세대 = c.hhld_cnt_sum, 붙일 = COUNT(*),
               이미붙음 = MAX(s.붙음), 번호전체 = MAX(s.전체), 계약 = MIN(t.deal_ymd) + '~' + MAX(t.deal_ymd), 원천이름 = MIN(t.bld_nm), 다른이름 = MAX(t.bld_nm),
               종류 = STRING_AGG(CAST(t.trade_kind AS NVARCHAR(MAX)), ',') WITHIN GROUP (ORDER BY t.trade_kind)
          FROM #f f JOIN silver.rtms_trade t ON t.trade_sk = f.trade_sk JOIN gold.complex c ON c.complex_id = f.cid JOIN #s s ON s.apt_seq = t.apt_seq
         GROUP BY f.cid, c.complex_nm, LEFT(c.oldest_use_apr, 4), c.hhld_cnt_sum ORDER BY COUNT(*) DESC;
        SELECT 시도 = LEFT(t.sgg_cd, 2), 종류 = t.trade_kind, 줄 = COUNT(*) FROM #f f JOIN silver.rtms_trade t ON t.trade_sk = f.trade_sk GROUP BY LEFT(t.sgg_cd, 2), t.trade_kind ORDER BY 3 DESC;
        RETURN;
    END
    BEGIN TRAN;
        INSERT INTO ops.rtms_rematch_log (run_id, trade_sk, old_cid, new_cid) SELECT @run, trade_sk, NULL, cid FROM #f;
        UPDATE t SET t.match_complex_id = f.cid, t.match_note = N'425: 같은 aptSeq 이어받기'
          FROM silver.rtms_trade t JOIN #f f ON f.trade_sk = t.trade_sk WHERE t.match_complex_id IS NULL;
    COMMIT;
END
GO
