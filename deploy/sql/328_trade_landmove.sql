/* ============================================================
   328_trade_landmove : 단지에 안 붙은 주거 실거래 — 옛 지번이 **토지이동으로 합병**된 곳 (2026-10-23 사장님 "2번 ㅇㅇ 정책에만 잘 적어놔")
   ★ 규칙(이름은 안 본다 · 모두 맞아야):
       ① 거래 지번이 지금 지적도에 없다 · 아파트·연립·단독(APT · RH · SH) · 분양권·입주권 아님 · 아직 단지 없음
       ② 그 지번의 토지이동이력 **마지막 줄** = 'N번과 합병되어 말소'(원문) · 같은 법정동의 N 필지가 지금 있다
       ③ N 필지의 세대 단지가 **하나**
       ④ 계약일 ≥ 그 단지 사용승인일 — 사용승인 전 계약은 헐린 옛 건물 거래다(장미타운 → 은평자이더스타 등 1,314건, 붙이면 안 됨)
   ★ 실측(서울 첫 판): 능마루빌라(2020-12-24 · 11세대) 전월세 18건(2021-03~2026-02, 옛 지번 2021-07-13 합병).
   ★ ops.rtms_rematch_log 에 남긴다(old_cid NULL) — 되돌리기는 282 와 같다. 318 프로시저 끝에서 부른다(적재 끝마다).
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE gold.usp_match_trade_landmove
    @dry BIT = 0, @n INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @run INT = ISNULL((SELECT MAX(run_id) FROM ops.rtms_rematch_log), 0) + 1;
    IF OBJECT_ID('tempdb..#t') IS NOT NULL DROP TABLE #t;
    SELECT t.trade_sk, t.match_pnu, t.deal_ymd
      INTO #t FROM silver.rtms_trade t
     WHERE t.match_complex_id IS NULL AND t.match_pnu IS NOT NULL
       AND (t.trade_kind LIKE 'APT%' OR t.trade_kind LIKE 'RH%' OR t.trade_kind LIKE 'SH%') AND t.trade_kind NOT LIKE 'SILV%'
       AND NOT EXISTS (SELECT 1 FROM silver.cadastral_parcel p WHERE p.pnu = t.match_pnu AND p.is_current = 1);
    IF OBJECT_ID('tempdb..#m') IS NOT NULL DROP TABLE #m;
    SELECT DISTINCT t.match_pnu,
           대상 = LEFT(h.이동사유, CASE WHEN CHARINDEX(N'번과 합병되어 말소', h.이동사유) > 0 THEN CHARINDEX(N'번과 합병되어 말소', h.이동사유) - 1 ELSE 0 END)
      INTO #m FROM (SELECT DISTINCT match_pnu FROM #t) t
     CROSS APPLY (SELECT TOP 1 x.이동사유 FROM silver.land_move_hist x WHERE x.pnu = t.match_pnu ORDER BY x.이동일 DESC, x.이력순번 DESC) h
     WHERE h.이동사유 LIKE N'%번과 합병되어 말소';
    DELETE FROM #m WHERE 대상 LIKE '%[^0-9-]%' OR LEN(대상) NOT BETWEEN 1 AND 9 OR 대상 LIKE '%-%-%';
    ALTER TABLE #m ADD 새 CHAR(19);
    UPDATE #m SET 새 = LEFT(match_pnu, 11) + RIGHT('0000' + CASE WHEN CHARINDEX('-', 대상) > 0 THEN LEFT(대상, CHARINDEX('-', 대상) - 1) ELSE 대상 END, 4)
                     + RIGHT('0000' + CASE WHEN CHARINDEX('-', 대상) > 0 THEN SUBSTRING(대상, CHARINDEX('-', 대상) + 1, 10) ELSE '0' END, 4);
    DELETE m FROM #m m WHERE NOT EXISTS (SELECT 1 FROM silver.cadastral_parcel p WHERE p.pnu = m.새 AND p.is_current = 1);
    IF OBJECT_ID('tempdb..#c') IS NOT NULL DROP TABLE #c;
    SELECT m.match_pnu, complex_id = MIN(c.complex_id), 준공 = MIN(c.oldest_use_apr)
      INTO #c FROM #m m
      JOIN gold.complex_pnu cp ON cp.pnu = m.새
      JOIN gold.complex c ON c.complex_id = cp.complex_id AND c.is_active = 1 AND c.merged_into IS NULL AND c.hhld_cnt_sum > 0 AND LEN(c.oldest_use_apr) = 8
     GROUP BY m.match_pnu HAVING COUNT(DISTINCT c.complex_id) = 1;
    IF OBJECT_ID('tempdb..#f') IS NOT NULL DROP TABLE #f;
    SELECT t.trade_sk, c.complex_id INTO #f FROM #t t JOIN #c c ON c.match_pnu = t.match_pnu WHERE t.deal_ymd >= c.준공;
    SET @n = (SELECT COUNT(*) FROM #f);
    IF @dry = 1
    BEGIN
        SELECT r = (SELECT 붙을 = @n, 단지 = (SELECT COUNT(DISTINCT complex_id) FROM #f),
                    막힘_사용승인전 = (SELECT COUNT(*) FROM #t t JOIN #c c ON c.match_pnu = t.match_pnu WHERE t.deal_ymd < c.준공),
                    예 = (SELECT c.complex_nm, 실거래이름 = MAX(r.bld_nm), n = COUNT(*), 처음 = MIN(r.deal_ymd), 끝 = MAX(r.deal_ymd), 사용승인 = MIN(c.oldest_use_apr)
                           FROM #f f JOIN gold.complex c ON c.complex_id = f.complex_id JOIN silver.rtms_trade r ON r.trade_sk = f.trade_sk
                          GROUP BY c.complex_nm FOR JSON PATH)
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        RETURN;
    END
    IF @n > 0
    BEGIN
        BEGIN TRAN;
            INSERT INTO ops.rtms_rematch_log (run_id, trade_sk, old_cid, new_cid) SELECT @run, trade_sk, NULL, complex_id FROM #f;
            UPDATE t SET t.match_complex_id = f.complex_id FROM silver.rtms_trade t JOIN #f f ON f.trade_sk = t.trade_sk WHERE t.match_complex_id IS NULL;
        COMMIT;
    END
END
GO
EXEC gold.usp_match_trade_landmove @dry = 1;
