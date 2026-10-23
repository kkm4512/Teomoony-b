/* ============================================================
   318_trade_kapt : 단지에 안 붙은 아파트 실거래 → **K-apt 지번** · **도로명코드(마스터 방식)** 로 그 단지에 (2026-10-23 새벽, 사장님 "확실한건만 매칭 기준을 정리해")
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
    SELECT t.trade_sk, t.complex_id, 길 = CAST(N'K-apt 지번' AS NVARCHAR(20))
      INTO #f
      FROM #t t
      JOIN (SELECT apt_seq, match_pnu, 처음 = MIN(deal_ymd), 끝 = MAX(deal_ymd) FROM silver.rtms_trade
             WHERE trade_kind NOT LIKE 'SILV%' AND apt_seq IS NOT NULL AND match_pnu IN (SELECT pnu FROM #kp)
             GROUP BY apt_seq, match_pnu) g ON g.apt_seq = t.apt_seq AND g.match_pnu = t.match_pnu
     WHERE g.처음 >= CONVERT(CHAR(8), DATEADD(YEAR, -1, TRY_CONVERT(DATE, t.준공)), 112)
        /* 2026-10-23 사장님 "확실한건만 · ㄱㄱ"(LH수서1·2: 공공임대 전월세가 사용승인 1~2년 전에 신고됨):
           그 지번에 폐쇄 대장이 없고 · 같은 aptSeq 가 **사용승인 뒤에도 계속 거래**되고 · 첫 계약이 사용승인 3년 전 이후.
           ★ '폐쇄 대장 없음' 만으로는 모자랐다 — 래미안도곡카운티 지번에 옛 '진달래'(2006~) 거래가 폐쇄 대장 없이 있었다(첫 판에서 잡음).
             헐린 옛 건물은 새 건물 사용승인 **뒤에** 거래될 수 없으므로 '뒤에도 거래' 가 옛 건물을 막는다. */
        OR (NOT EXISTS (SELECT 1 FROM gold.closed_site s WHERE s.pnu = t.match_pnu)
            AND g.끝 >= t.준공
            AND g.처음 >= CONVERT(CHAR(8), DATEADD(YEAR, -3, TRY_CONVERT(DATE, t.준공)), 112));
       /* (첫 판에는 '폐쇄 대장이 있으면 닫힌 날 이후만' 도 걸었다 — 택지의 옛 비주거 대장이 새 단지 입주 뒤에 닫힌 곳(강동리엔파크11단지)까지 막아서 뺐다.
          옛 아파트 거래는 aptSeq 의 첫 계약이 사용승인 1년 전보다 훨씬 이르므로 위 조건 하나로 걸러진다 — 헐고 새로 짓는 데 1년 안에 끝나는 곳은 없다.) */

    /* ② 2026-10-23 사장님 "법정동 도로명 모두 마스터와 같은 방식" — 실거래의 **도로명코드 + 건물본번 + 부번** = 대장 동의 [na_road_cd + na_main_bun + na_sub_bun](지상)
         · 그 주소의 세대 단지가 하나 · 옛 건물 거래 아님(그 지번 폐쇄 대장이 닫히기 전 계약이 아님) · 같은 aptSeq·같은 도로명주소의 첫 계약이 사용승인 1년 전 이후
         (옛 건물이 같은 건물번호를 물려준 곳 — 가락시영 '송파대로 345' = 헬리오시티 — 을 막는다) */
    IF OBJECT_ID('tempdb..#rb') IS NOT NULL DROP TABLE #rb;
    SELECT b.na_road_cd, bm = TRY_CAST(b.na_main_bun AS INT), bs = ISNULL(TRY_CAST(b.na_sub_bun AS INT), 0),
           complex_id = MIN(cb.complex_id), 준공 = MIN(c.oldest_use_apr)
      INTO #rb
      FROM silver.bld_title b JOIN gold.complex_bld cb ON cb.mgm_bldrgst_pk = b.mgm_bldrgst_pk
      JOIN gold.complex c ON c.complex_id = cb.complex_id AND c.is_active = 1 AND c.merged_into IS NULL AND c.hhld_cnt_sum > 0 AND LEN(c.oldest_use_apr) = 8
     WHERE b.is_current = 1 AND b.na_road_cd IS NOT NULL AND ISNULL(b.na_ugrnd_cd, '0') = '0' AND TRY_CAST(b.na_main_bun AS INT) > 0
     GROUP BY b.na_road_cd, TRY_CAST(b.na_main_bun AS INT), ISNULL(TRY_CAST(b.na_sub_bun AS INT), 0)
    HAVING COUNT(DISTINCT cb.complex_id) = 1;
    CREATE CLUSTERED INDEX x ON #rb (na_road_cd, bm, bs);
    IF OBJECT_ID('tempdb..#rt') IS NOT NULL DROP TABLE #rt;
    SELECT t.trade_sk, t.apt_seq, t.road_cd, rb = TRY_CAST(t.road_bonbun AS INT), rs = ISNULL(TRY_CAST(t.road_bubun AS INT), 0), t.deal_ymd, r.complex_id, r.준공, t.match_pnu
      INTO #rt
      FROM silver.rtms_trade t
      JOIN #rb r ON r.na_road_cd = t.road_cd AND r.bm = TRY_CAST(t.road_bonbun AS INT) AND r.bs = ISNULL(TRY_CAST(t.road_bubun AS INT), 0)
     WHERE t.match_complex_id IS NULL AND t.trade_kind LIKE 'APT%' AND t.apt_seq IS NOT NULL AND t.road_cd IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM #f f WHERE f.trade_sk = t.trade_sk)
       AND NOT EXISTS (SELECT 1 FROM gold.closed_site s WHERE s.pnu = t.match_pnu AND LEN(s.shter_day) = 8 AND t.deal_ymd <= s.shter_day);
    INSERT INTO #f (trade_sk, complex_id, 길)
    SELECT t.trade_sk, t.complex_id, N'도로명코드'
      FROM #rt t
      JOIN (SELECT apt_seq, road_cd, rb, rs, 처음 = MIN(deal_ymd), 끝 = MAX(deal_ymd) FROM #rt GROUP BY apt_seq, road_cd, rb, rs) g
        ON g.apt_seq = t.apt_seq AND g.road_cd = t.road_cd AND g.rb = t.rb AND g.rs = t.rs
     WHERE g.처음 >= CONVERT(CHAR(8), DATEADD(YEAR, -1, TRY_CONVERT(DATE, t.준공)), 112)
        /* ① 과 같은 완화(폐쇄 대장 없음 · 사용승인 뒤에도 거래 · 첫 계약 3년 안) — LH수서1단지 */
        OR (NOT EXISTS (SELECT 1 FROM gold.closed_site s WHERE s.pnu = t.match_pnu)
            AND g.끝 >= t.준공
            AND g.처음 >= CONVERT(CHAR(8), DATEADD(YEAR, -3, TRY_CONVERT(DATE, t.준공)), 112));

    SET @n = (SELECT COUNT(*) FROM #f);
    IF @dry = 1
    BEGIN
        SELECT 붙을 = @n, 단지 = (SELECT COUNT(DISTINCT complex_id) FROM #f), 후보 = (SELECT COUNT(*) FROM #t),
               길별 = (SELECT 길, n = COUNT(*), 단지 = COUNT(DISTINCT complex_id) FROM #f GROUP BY 길 FOR JSON PATH),
               도로예 = (SELECT TOP 25 c.complex_nm, 실거래이름 = MAX(t.bld_nm), n = COUNT(*), 처음 = MIN(t.deal_ymd), 준공 = MIN(c.oldest_use_apr)
                       FROM #f f JOIN gold.complex c ON c.complex_id = f.complex_id JOIN silver.rtms_trade t ON t.trade_sk = f.trade_sk
                      WHERE f.길 = N'도로명코드' GROUP BY c.complex_nm ORDER BY n DESC FOR JSON PATH),
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
    /* 328 (2026-10-23): 옛 지번이 토지이동으로 합병된 주거 거래 → 합병된 필지의 세대 단지(사용승인 뒤 계약만) */
    DECLARE @lm INT = 0;
    IF OBJECT_ID('gold.usp_match_trade_landmove') IS NOT NULL EXEC gold.usp_match_trade_landmove @dry = 0, @n = @lm OUTPUT;
    SET @n = @n + ISNULL(@lm, 0);
    /* 329 (2026-10-23): 옛 건물 거래가 새 건물에 붙은 것을 뗀다(282 가 지번으로 다시 붙여도 여기서 다시 뗀다) */
    DECLARE @dt INT = 0;
    IF OBJECT_ID('gold.usp_detach_old_building_trades') IS NOT NULL EXEC gold.usp_detach_old_building_trades @dry = 0, @n = @dt OUTPUT;
END
GO
EXEC gold.usp_match_trade_kapt @dry = 1;   -- 미리보기(실제 붙이기는 282 안에서 · 또는 @dry = 0)
