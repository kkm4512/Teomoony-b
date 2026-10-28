/* 372 (2026-10-28) 실거래 — 한 필지에 세대 있는 단지가 여럿일 때 거래 원문의 건축년도(+전용면적)로 고르기 · 맞는 단지가 없으면 안 붙임.
   사장님: "실거래를 지번으로만 이어? 땅 하나에 건물 여러개가 있을 수 있는데 위험하지 않나" → 잰 것(애매 필지 거래 68.4만 · 연도 다름 5.8만) → "일단 12 ㄱㄱ".
   원문 칸은 손대지 않는다 — 연결 칸(match_complex_id · match_note)만. 옮긴 것 ops.rtms_rematch_log · 뗀 것 ops.rtms_unmatch_log.
   EXEC gold.usp_match_complex_trade @dry = 1 → 결과만 보기. */
CREATE OR ALTER PROCEDURE gold.usp_match_complex_trade
    @dry BIT = 0
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

    /* ★ 372 (2026-10-28 사장님 "땅 하나에 건물 여러개가 있을 수 있는데 위험하지 않나" → "12 ㄱㄱ"):
       한 필지에 **세대 있는 단지가 둘 이상**이면 지번만으로는 어느 단지 거래인지 모른다(은하수·샛별아파트).
       거래 원문의 **건축년도**(+ 전용면적)로 고른다 — 이름은 안 본다.
         · 후보 = 그 필지의 세대 있는 단지. 후보의 연도 = 그 단지 주택 동들의 사용승인 연도(여럿일 수 있다).
         · 건축년도가 맞고 전용면적도 맞는(그 단지 호 면적 ±0.05㎡ · 면적 자료가 없으면 통과) 후보가 **딱 하나** → 그 단지(Y)
         · 모든 후보의 연도를 아는데 **±3년 안에도** 맞는 후보가 하나도 없다 → 안 붙인다(N · 조용히 틀린 값보다 빈 값) · match_note '372:'
         · 그 밖(여럿 맞음 · 연도 모르는 후보 있음 · 건축년도 없음) → 지금 규칙 그대로(D) */
    IF OBJECT_ID('tempdb..#cand') IS NOT NULL DROP TABLE #cand;
    SELECT cp.pnu, cp.complex_id INTO #cand
      FROM gold.complex_pnu cp JOIN #c x ON x.complex_id = cp.complex_id AND x.hhld > 0
     WHERE cp.pnu IN (SELECT cp2.pnu FROM gold.complex_pnu cp2 JOIN #c x2 ON x2.complex_id = cp2.complex_id AND x2.hhld > 0
                       GROUP BY cp2.pnu HAVING COUNT(DISTINCT cp2.complex_id) > 1);
    CREATE CLUSTERED INDEX x ON #cand (pnu, complex_id);
    IF OBJECT_ID('tempdb..#cy') IS NOT NULL DROP TABLE #cy;
    SELECT DISTINCT cb.complex_id, yr = LEFT(tt.use_apr_day, 4) INTO #cy
      FROM gold.complex_bld cb JOIN silver.bld_title tt ON tt.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND tt.is_current = 1
     WHERE cb.complex_id IN (SELECT complex_id FROM #cand) AND tt.main_purps_nm LIKE N'%주택%'
       AND LEN(tt.use_apr_day) >= 4 AND tt.use_apr_day NOT LIKE '%[^0-9]%';
    CREATE CLUSTERED INDEX x ON #cy (complex_id, yr);
    IF OBJECT_ID('tempdb..#ty') IS NOT NULL DROP TABLE #ty;
    SELECT t.trade_sk, t.match_pnu, by_ = LEFT(LTRIM(CAST(t.build_year AS VARCHAR(10))), 4), ar = t.exclu_use_ar INTO #ty
      FROM silver.rtms_trade t
     WHERE t.match_pnu IN (SELECT pnu FROM #cand)
       AND (t.trade_kind LIKE 'APT%' OR t.trade_kind LIKE 'RH%') AND t.trade_kind NOT LIKE 'SILV%'
       AND LEN(LTRIM(CAST(t.build_year AS VARCHAR(10)))) = 4;
    CREATE CLUSTERED INDEX x ON #ty (trade_sk);
    IF OBJECT_ID('tempdb..#k') IS NOT NULL DROP TABLE #k;
    SELECT y.trade_sk, c.complex_id,
           ym = CASE WHEN EXISTS (SELECT 1 FROM #cy a WHERE a.complex_id = c.complex_id AND a.yr = y.by_) THEN 1 ELSE 0 END,
           yk = CASE WHEN EXISTS (SELECT 1 FROM #cy a WHERE a.complex_id = c.complex_id) THEN 1 ELSE 0 END,
           /* 떼기(N)는 ±3년도 안 맞을 때만 — 건축년도와 사용승인 연도가 어긋나는 곳이 있다(용상4주공 1987 ↔ 대장 1988 · 힐스테이트 리버시티 2단지 2020 ↔ 2022).
              뗄 것은 헐린 옛 건물 거래(1978~1990 거래 ↔ 지금 건물 2014~2017)처럼 크게 어긋나는 것 */
           y1 = CASE WHEN EXISTS (SELECT 1 FROM #cy a WHERE a.complex_id = c.complex_id AND ABS(TRY_CAST(a.yr AS INT) - TRY_CAST(y.by_ AS INT)) <= 3) THEN 1 ELSE 0 END,
           ap = CASE WHEN y.ar IS NULL OR NOT EXISTS (SELECT 1 FROM gold.complex_area a WHERE a.complex_id = c.complex_id)
                       OR EXISTS (SELECT 1 FROM gold.complex_area a WHERE a.complex_id = c.complex_id AND ABS(a.전용 - y.ar) <= 0.05) THEN 1 ELSE 0 END
      INTO #k FROM #ty y JOIN #cand c ON c.pnu = y.match_pnu;
    IF OBJECT_ID('tempdb..#d') IS NOT NULL DROP TABLE #d;
    SELECT trade_sk,
           결정 = CASE WHEN SUM(y1) = 0 AND SUM(1 - yk) = 0 THEN 'N' WHEN SUM(ym * ap) = 1 THEN 'Y' ELSE 'D' END,
           cid = MIN(CASE WHEN ym = 1 AND ap = 1 THEN complex_id END)
      INTO #d FROM #k GROUP BY trade_sk;
    CREATE CLUSTERED INDEX x ON #d (trade_sk);

    /* 바꿀 거래를 먼저 뽑는다 */
    IF OBJECT_ID('tempdb..#f') IS NOT NULL DROP TABLE #f;
    SELECT trade_sk, old_cid, new_cid, 결정 INTO #f FROM (
      SELECT t.trade_sk, old_cid = t.match_complex_id,
             new_cid = CASE WHEN d.결정 = 'N' THEN NULL WHEN d.결정 = 'Y' THEN d.cid ELSE p.complex_id END,
             결정 = ISNULL(d.결정, '-')
        FROM silver.rtms_trade t
        JOIN #p p ON p.pnu = t.match_pnu
                 AND p.grp = CASE WHEN t.trade_kind LIKE 'APT%' OR t.trade_kind LIKE 'RH%' OR t.trade_kind LIKE 'SH%' THEN 'R'
                                  WHEN t.trade_kind LIKE 'OFFI%' THEN 'O' ELSE 'X' END
        LEFT JOIN #d d ON d.trade_sk = t.trade_sk
       WHERE t.match_pnu IS NOT NULL
         AND t.trade_kind NOT LIKE 'SILV%'   -- ★ 2026-10-21: 분양권·입주권은 **사업 전 지번**이라 철거 전 옛 단지에 붙으면 틀린다 — 안 붙인다(291)
    ) z
     WHERE NOT (old_cid IS NULL AND new_cid IS NULL) AND (old_cid IS NULL OR new_cid IS NULL OR old_cid <> new_cid);
    CREATE CLUSTERED INDEX x ON #f (trade_sk);
    DECLARE @n INT = (SELECT COUNT(*) FROM #f),
            @새로 INT = (SELECT COUNT(*) FROM #f WHERE old_cid IS NULL);
    IF @dry = 1
    BEGIN
        SELECT 결정, 거래 = COUNT(*) FROM #d GROUP BY 결정 ORDER BY 결정;
        SELECT 결정, 바뀜 = COUNT(*), 뗌 = SUM(CASE WHEN new_cid IS NULL THEN 1 ELSE 0 END), 새로 = SUM(CASE WHEN old_cid IS NULL THEN 1 ELSE 0 END)
          FROM #f GROUP BY 결정 ORDER BY 결정;
        SELECT TOP 25 f.결정, 거래 = COUNT(*), 지금 = MIN(CONCAT(f.old_cid, ':', co.complex_nm)), 새 = MIN(CONCAT(f.new_cid, ':', cn.complex_nm)),
               건축년도 = MIN(y.by_), 거래이름 = MAX(t.bld_nm)
          FROM #f f JOIN #ty y ON y.trade_sk = f.trade_sk JOIN silver.rtms_trade t ON t.trade_sk = f.trade_sk
          LEFT JOIN gold.complex co ON co.complex_id = f.old_cid LEFT JOIN gold.complex cn ON cn.complex_id = f.new_cid
         WHERE f.결정 IN ('Y', 'N') GROUP BY f.결정, f.old_cid, f.new_cid ORDER BY COUNT(*) DESC;
        RETURN;
    END

    /* 2만 건씩 — 기록 먼저, 그다음 바꾼다(같은 트랜잭션) */
    DECLARE @lo BIGINT = 0, @hi BIGINT;
    WHILE 1 = 1
    BEGIN
        SELECT @hi = MAX(trade_sk) FROM (SELECT TOP (4000) trade_sk FROM #f WHERE trade_sk > @lo ORDER BY trade_sk) s;
        IF @hi IS NULL BREAK;
        BEGIN TRAN;
            INSERT INTO ops.rtms_rematch_log (run_id, trade_sk, old_cid, new_cid)
            SELECT @run, trade_sk, old_cid, new_cid FROM #f WHERE trade_sk > @lo AND trade_sk <= @hi AND old_cid IS NOT NULL AND new_cid IS NOT NULL;
            /* 372: 떼어낸 것은 new_cid 가 NULL 이라 rematch_log 에 못 적는다 → ops.rtms_unmatch_log(363 표) */
            INSERT INTO ops.rtms_unmatch_log (trade_sk, old_pnu, old_cid, old_method, why)
            SELECT f.trade_sk, t.match_pnu, f.old_cid, t.match_method, N'372 한 필지 여러 단지 · 건축년도 맞는 단지 없음'
              FROM #f f JOIN silver.rtms_trade t ON t.trade_sk = f.trade_sk
             WHERE f.trade_sk > @lo AND f.trade_sk <= @hi AND f.old_cid IS NOT NULL AND f.new_cid IS NULL;
            UPDATE t SET t.match_complex_id = f.new_cid,
                         t.match_note = CASE WHEN f.new_cid IS NULL THEN N'372: 한 필지 여러 단지 · 건축년도 맞는 단지 없음'
                                             WHEN t.match_note LIKE N'372:%' THEN NULL ELSE t.match_note END
              FROM silver.rtms_trade t JOIN #f f ON f.trade_sk = t.trade_sk
             WHERE f.trade_sk > @lo AND f.trade_sk <= @hi;
        COMMIT;
        SET @lo = @hi;
    END

    /* ★ 2026-10-24: 안쪽 프로시저(318)도 #f · #t 를 **다른 칸으로** 만든다. 바깥 #f 가 살아 있으면 안쪽 문장이 바깥 #f 에 묶여
       'Invalid column name complex_id' 로 죽었다(안양 실거래 재매칭에서 발견). 셀 것은 먼저 세고 바깥 임시표를 치운다. */
    DECLARE @여럿 INT = (SELECT COUNT(*) FROM #c);
    DROP TABLE #f; DROP TABLE #p; DROP TABLE #c; DROP TABLE #k; DROP TABLE #d; DROP TABLE #ty; DROP TABLE #cy; DROP TABLE #cand;

    /* 318 (2026-10-23): 필지로 못 붙은 아파트 거래 → K-apt 지번(사업 전 지번)으로. 결과 행을 안 내보낸다 — 아래 한 행만 나간다(load_rtms.py) */
    DECLARE @kapt INT = 0;
    IF OBJECT_ID('gold.usp_match_trade_kapt') IS NOT NULL EXEC gold.usp_match_trade_kapt @dry = 0, @n = @kapt OUTPUT;

    SELECT 회차 = @run, 바꿈 = @n - @새로, 새로붙음 = @새로,
           여럿필지단지 = @여럿, 초 = DATEDIFF(SECOND, @t0, SYSDATETIME()), K_apt지번 = @kapt;
END
GO
/* 318 K-apt 도로명 길(②)은 단지 없는 아파트 거래를 도로명주소로 붙인다 — 372 가 일부러 뗀 거래를 다시 붙이면 날마다 붙였다 뗐다 한다 → 건너뛴다 */
