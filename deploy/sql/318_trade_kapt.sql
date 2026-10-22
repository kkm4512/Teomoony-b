/* ============================================================
   318_trade_kapt : 단지에 안 붙은 아파트 실거래 → **K-apt 지번**으로 그 단지에 (2026-10-23 새벽, 사장님 "확실한건만 매칭 기준을 정리해")
   ★ 왜(실측, 서울): 필지는 찾았는데 단지가 없는 아파트·연립·오피스텔 거래 18.3만. 그중 새 단지 거래가 상당수다 —
     정비사업·택지 단지는 이전고시·지번 정리 전까지 실거래가 **사업 전 지번**(메이플자이 '잠원동 60-3' · 강동리버스트4단지 '강일동 114')으로
     신고되는데, 대장은 새 지번(잠원동 167 · 강일동 742)이라 지번으로 안 만난다. 도로명도 옛 것(잠원로4길 50)이라 도로명으로도 안 만난다.
     K-apt 는 같은 사업 전 지번(60-3 · 114)을 갖고 있고, K-apt ↔ 단지는 따로 이어져 있다(280 · 317).
   ★ 규칙(이름은 안 본다 · 모두 맞아야):
       ① 아파트 거래(APT_*) · 분양권·입주권 아님 · 아직 단지 없음 · 거래 지번 = K-apt 지번
       ② 그 K-apt 가 gold.complex_kapt 로 단지 하나에 이어져 있다 · 그 지번의 K-apt 들이 가리키는 단지가 **하나**
       ③ 그 지번은 대장 단지 필지가 아니다(필지 매칭 282 가 맡는 곳은 건드리지 않는다)
       ④ **같은 아파트 번호(aptSeq)** 의 그 지번 거래 중 가장 이른 계약이 그 단지 사용승인 1년 전 이후 — 옛 건물(재건축 전) 거래는
          옛 번호로 훨씬 일찍부터 있으니 여기서 걸러진다(헐고 새로 짓는 데 1년 안에 끝나는 곳은 없다).
   ★ 원본 칸(match_pnu · match_method)은 안 바꾼다. 붙인 것은 ops.rtms_rematch_log 에 (old_cid NULL) 남는다 — 되돌리기는 282 와 같다.
   ★ 282 프로시저 안(필지 매칭 다음)에서 부른다 — 적재 끝마다 같이 돈다. 결과 행은 안 내보낸다(load_rtms.py 가 282 의 한 행을 읽는다).
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE gold.usp_match_trade_kapt
    @dry BIT = 0, @n INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @run INT = ISNULL((SELECT MAX(run_id) FROM ops.rtms_rematch_log), 0) + 1;
    /* K-apt 지번 → 단지(하나일 때만) */
    IF OBJECT_ID('tempdb..#kp') IS NOT NULL DROP TABLE #kp;
    SELECT k.pnu, complex_id = MIN(ck.complex_id), 준공 = MIN(c.oldest_use_apr)
      INTO #kp
      FROM silver.kapt_complex k
      JOIN gold.complex_kapt ck ON ck.kapt_code = k.kapt_code
      JOIN gold.complex c ON c.complex_id = ck.complex_id AND c.is_active = 1 AND c.merged_into IS NULL AND c.hhld_cnt_sum > 0
     WHERE k.is_current = 1 AND k.pnu IS NOT NULL AND LEN(c.oldest_use_apr) = 8
       AND NOT EXISTS (SELECT 1 FROM gold.complex_pnu cp WHERE cp.pnu = k.pnu)
     GROUP BY k.pnu
    HAVING COUNT(DISTINCT ck.complex_id) = 1;
    CREATE CLUSTERED INDEX x ON #kp (pnu);
    /* 후보 거래 */
    IF OBJECT_ID('tempdb..#t') IS NOT NULL DROP TABLE #t;
    SELECT t.trade_sk, t.apt_seq, t.match_pnu, t.deal_ymd, p.complex_id, p.준공,
           닫힘 = (SELECT MAX(s.shter_day) FROM gold.closed_site s WHERE s.pnu = t.match_pnu AND LEN(s.shter_day) = 8)
      INTO #t
      FROM silver.rtms_trade t JOIN #kp p ON p.pnu = t.match_pnu
     WHERE t.match_complex_id IS NULL AND t.trade_kind LIKE 'APT%' AND t.trade_kind NOT LIKE 'SILV%' AND t.apt_seq IS NOT NULL;
    /* aptSeq 단위로 가장 이른 계약 */
    IF OBJECT_ID('tempdb..#f') IS NOT NULL DROP TABLE #f;
    SELECT t.trade_sk, t.complex_id
      INTO #f
      FROM #t t
      JOIN (SELECT apt_seq, match_pnu, 처음 = MIN(deal_ymd) FROM silver.rtms_trade
             WHERE trade_kind NOT LIKE 'SILV%' AND apt_seq IS NOT NULL AND match_pnu IN (SELECT pnu FROM #kp)
             GROUP BY apt_seq, match_pnu) g ON g.apt_seq = t.apt_seq AND g.match_pnu = t.match_pnu
     WHERE g.처음 >= CONVERT(CHAR(8), DATEADD(YEAR, -1, TRY_CONVERT(DATE, t.준공)), 112);
       /* (첫 판에는 '폐쇄 대장이 있으면 닫힌 날 이후만' 도 걸었다 — 택지의 옛 비주거 대장이 새 단지 입주 뒤에 닫힌 곳(강동리엔파크11단지)까지 막아서 뺐다.
          옛 아파트 거래는 aptSeq 의 첫 계약이 사용승인 1년 전보다 훨씬 이르므로 위 조건 하나로 걸러진다 — 헐고 새로 짓는 데 1년 안에 끝나는 곳은 없다.) */
    SET @n = (SELECT COUNT(*) FROM #f);
    IF @dry = 1
    BEGIN
        SELECT 붙을 = @n, 단지 = (SELECT COUNT(DISTINCT complex_id) FROM #f), 후보 = (SELECT COUNT(*) FROM #t),
               예 = (SELECT TOP 20 c.complex_nm, 실거래이름 = MAX(t.bld_nm), n = COUNT(*), 처음 = MIN(t.deal_ymd), 준공 = MIN(c.oldest_use_apr)
                       FROM #f f JOIN gold.complex c ON c.complex_id = f.complex_id JOIN silver.rtms_trade t ON t.trade_sk = f.trade_sk
                      GROUP BY c.complex_nm ORDER BY n DESC FOR JSON PATH),
               빠진 = (SELECT TOP 10 c.complex_nm, 실거래이름 = MAX(r.bld_nm), n = COUNT(*), 처음 = MIN(t.deal_ymd), 준공 = MIN(t.준공)
                       FROM #t t JOIN gold.complex c ON c.complex_id = t.complex_id JOIN silver.rtms_trade r ON r.trade_sk = t.trade_sk
                      WHERE t.trade_sk NOT IN (SELECT trade_sk FROM #f) GROUP BY c.complex_nm ORDER BY n DESC FOR JSON PATH);
        RETURN;
    END
    DECLARE @lo BIGINT = 0, @hi BIGINT;
    WHILE 1 = 1
    BEGIN
        SELECT @hi = MAX(trade_sk) FROM (SELECT TOP (20000) trade_sk FROM #f WHERE trade_sk > @lo ORDER BY trade_sk) s;
        IF @hi IS NULL BREAK;
        BEGIN TRAN;
            INSERT INTO ops.rtms_rematch_log (run_id, trade_sk, old_cid, new_cid)
            SELECT @run, trade_sk, NULL, complex_id FROM #f WHERE trade_sk > @lo AND trade_sk <= @hi;
            UPDATE t SET t.match_complex_id = f.complex_id
              FROM silver.rtms_trade t JOIN #f f ON f.trade_sk = t.trade_sk
             WHERE f.trade_sk > @lo AND f.trade_sk <= @hi AND t.match_complex_id IS NULL;
        COMMIT;
        SET @lo = @hi;
    END
END
GO
EXEC gold.usp_match_trade_kapt @dry = 1;   -- 미리보기(실제 붙이기는 282 안에서 · 또는 @dry = 0)
