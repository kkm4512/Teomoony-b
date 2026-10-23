/* ============================================================
   330_merge_kapt_plan : K-apt 단지 하나 = 대장 조각 여럿 — 묶을 **계획만** 만든다 (2026-10-23 17:14 사장님 "ㄱㄱ")
   ★ 아무 단지도 바꾸지 않는다. ops.complex_merge_plan_kapt(파생)에 적고 요약 · 보기만 낸다. 적용은 331(본 뒤에).
   ★ 왜(11-236 점검): K-apt 안 이어진 310 중 255 가 '필지에 세대 단지 하나' 인데 세대 차가 커서 못 이었다 —
     대장은 총괄표제부(root)마다 단지 하나라, 한 단지가 필지마다 조각이 된다.
     예: 상계주공7단지 K-apt 2,634세대 = 대장 691번지 476 + 692번지 2,158 (정확히 합).
     286(같은 필지 + 단지번호 하나)은 조각이 **필지를 같이 쓸 때만** 묶어서 이건 못 묶었다.
   ★ 규칙 — 다 맞을 때만(이름은 안 본다)
     ① 아직 아무 단지에도 안 이어진 K-apt K(서울) · 공식 지번(K-apt pnu, 산·0번지 아님)에 세대 단지가 **하나**(C0) · C0 사용승인 = K 사용승인.
     ② C0 에 붙은 아파트 실거래(매매·전월세)의 국토부 단지번호(apt_seq)가 **하나 이하**(s).
        (실측: 상계주공7단지 거래는 국토부가 전부 691번지 · '상계주공7(고층)' 하나로 신고 — 692번지 조각은 거래가 0건)
     ③ 다른 조각 F = 같은 법정동 · **사용승인이 K 와 같은 날** · 주거 조각(주택 동 세대가 그 조각 세대의 절반 이상, 286 과 같은 기준) ·
        아직 K-apt 에 안 이어짐 · 단지번호가 **없거나 s 뿐**. 묶음 G = C0 + 그런 F **전부**(골라 맞추지 않는다).
     ④ **G 세대 합 = K 세대(정확히)** · 2~20 조각.
     ⑤ 한 조각이 두 K 의 묶음에 같이 들면 둘 다 묶지 않는다.
     남는 코드 = 세대 가장 많은 조각(같으면 코드 작은 쪽).
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
IF OBJECT_ID('ops.complex_merge_plan_kapt') IS NULL
CREATE TABLE ops.complex_merge_plan_kapt (
    kapt_code   VARCHAR(20)   NOT NULL,
    complex_id  INT           NOT NULL CONSTRAINT pk_cmpk PRIMARY KEY,
    남을코드    INT           NOT NULL,
    판정        NVARCHAR(20)  NOT NULL,
    세대        INT           NULL,
    이름        NVARCHAR(200) NULL,
    단지번호    VARCHAR(40)   NULL,
    kapt_이름   NVARCHAR(200) NULL,
    kapt_세대   INT           NULL,
    만든시각    DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);
GO
CREATE OR ALTER PROCEDURE gold.usp_plan_merge_kapt
AS
BEGIN
    SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    /* K 후보 */
    IF OBJECT_ID('tempdb..#k') IS NOT NULL DROP TABLE #k;
    SELECT k.kapt_code, k.kapt_name, k.pnu, k.bjd_code, k.kapt_usedate, 세대 = COALESCE(NULLIF(k.hhld_cnt, 0), k.ho_cnt)
      INTO #k FROM silver.kapt_complex k
     WHERE k.is_current = 1 AND k.bjd_code LIKE '11%' AND k.pnu IS NOT NULL
       AND SUBSTRING(k.pnu, 11, 1) = '1' AND SUBSTRING(k.pnu, 12, 4) <> '0000'
       AND COALESCE(NULLIF(k.hhld_cnt, 0), k.ho_cnt) > 0 AND NULLIF(k.kapt_usedate, '') IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM gold.complex_kapt x WHERE x.kapt_code = k.kapt_code);
    /* ① C0 */
    IF OBJECT_ID('tempdb..#k0') IS NOT NULL DROP TABLE #k0;
    SELECT k.*, c0 = MIN(c.complex_id) INTO #k0
      FROM #k k JOIN gold.complex_pnu cp ON cp.pnu = k.pnu
      JOIN gold.complex c ON c.complex_id = cp.complex_id AND c.is_active = 1 AND c.merged_into IS NULL AND c.hhld_cnt_sum > 0
     GROUP BY k.kapt_code, k.kapt_name, k.pnu, k.bjd_code, k.kapt_usedate, k.세대
    HAVING COUNT(DISTINCT c.complex_id) = 1;
    /* 단지마다 단지번호(붙은 아파트 매매·전월세) — 서울 세대 단지 */
    IF OBJECT_ID('tempdb..#sq') IS NOT NULL DROP TABLE #sq;
    SELECT DISTINCT cid = t.match_complex_id, s = t.apt_seq INTO #sq
      FROM silver.rtms_trade t JOIN gold.complex c ON c.complex_id = t.match_complex_id AND c.is_active = 1 AND c.hhld_cnt_sum > 0
     WHERE t.sgg_cd LIKE '11%' AND t.trade_kind IN ('APT_TRADE_DEV', 'APT_RENT') AND t.apt_seq IS NOT NULL;
    CREATE INDEX i1 ON #sq (cid); CREATE INDEX i2 ON #sq (s);
    IF OBJECT_ID('tempdb..#n') IS NOT NULL DROP TABLE #n;
    SELECT cid, n = COUNT(*) INTO #n FROM #sq GROUP BY cid;
    CREATE CLUSTERED INDEX i ON #n (cid);
    /* ② C0 사용승인 = K · 단지번호 하나 이하 */
    IF OBJECT_ID('tempdb..#ks') IS NOT NULL DROP TABLE #ks;
    SELECT k.*, s = (SELECT MIN(q.s) FROM #sq q WHERE q.cid = k.c0) INTO #ks
      FROM #k0 k JOIN gold.complex c ON c.complex_id = k.c0 AND c.oldest_use_apr = k.kapt_usedate
     WHERE ISNULL((SELECT n FROM #n WHERE cid = k.c0), 0) <= 1;
    /* ③ 같은 법정동 · 같은 날 · 세대 단지 */
    IF OBJECT_ID('tempdb..#f') IS NOT NULL DROP TABLE #f;
    SELECT k.kapt_code, cid = c.complex_id, c.hhld_cnt_sum, c.oldest_use_apr, c.complex_nm, C0 = CASE WHEN c.complex_id = k.c0 THEN 1 ELSE 0 END
      INTO #f FROM #ks k JOIN gold.complex c ON c.sigungu_cd + c.bjdong_cd = k.bjd_code AND c.oldest_use_apr = k.kapt_usedate
       AND c.is_active = 1 AND c.merged_into IS NULL AND c.hhld_cnt_sum > 0;
    /* 주거 조각(286 과 같은 기준) */
    IF OBJECT_ID('tempdb..#res') IS NOT NULL DROP TABLE #res;
    SELECT c.complex_id INTO #res
      FROM gold.complex c JOIN gold.complex_bld cb ON cb.complex_id = c.complex_id
      JOIN silver.bld_title t ON t.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND t.is_current = 1
     WHERE c.complex_id IN (SELECT cid FROM #f) AND t.main_purps_nm LIKE N'%주택%'
     GROUP BY c.complex_id
    HAVING SUM(ISNULL(t.hhld_cnt, 0)) * 2 >= MAX(c.hhld_cnt_sum);
    IF OBJECT_ID('tempdb..#g') IS NOT NULL DROP TABLE #g;
    SELECT f.* INTO #g FROM #f f JOIN #ks k ON k.kapt_code = f.kapt_code
     WHERE f.C0 = 1
        OR (EXISTS (SELECT 1 FROM #res r WHERE r.complex_id = f.cid)
            AND NOT EXISTS (SELECT 1 FROM gold.complex_kapt x WHERE x.complex_id = f.cid)
            AND NOT EXISTS (SELECT 1 FROM #sq q WHERE q.cid = f.cid AND (k.s IS NULL OR q.s <> k.s)));
    ALTER TABLE #g ADD 겹 BIT NOT NULL DEFAULT 0;
    UPDATE g SET 겹 = 1 FROM #g g WHERE EXISTS (SELECT 1 FROM #g g2 WHERE g2.cid = g.cid AND g2.kapt_code <> g.kapt_code);
    IF OBJECT_ID('tempdb..#v') IS NOT NULL DROP TABLE #v;
    SELECT k.kapt_code, k.kapt_name, k.세대, k.kapt_usedate, k.s,
           조각 = COUNT(*), 합 = SUM(g.hhld_cnt_sum),
           겹침 = SUM(CAST(g.겹 AS INT)),
           판정 = CAST(NULL AS NVARCHAR(20))
      INTO #v FROM #ks k JOIN #g g ON g.kapt_code = k.kapt_code
     GROUP BY k.kapt_code, k.kapt_name, k.세대, k.kapt_usedate, k.s;
    UPDATE #v SET 판정 = CASE WHEN 겹침 > 0 THEN N'겹침' WHEN 조각 < 2 THEN N'조각하나' WHEN 조각 > 20 THEN N'너무큼'
                              WHEN 합 <> 세대 THEN N'세대다름' ELSE N'묶음' END;
    BEGIN TRAN;
        DELETE FROM ops.complex_merge_plan_kapt;    -- 파생: 매번 새로
        INSERT INTO ops.complex_merge_plan_kapt (kapt_code, complex_id, 남을코드, 판정, 세대, 이름, 단지번호, kapt_이름, kapt_세대)
        SELECT v.kapt_code, g.cid,
               남을코드 = (SELECT TOP 1 g2.cid FROM #g g2 WHERE g2.kapt_code = v.kapt_code ORDER BY g2.hhld_cnt_sum DESC, g2.cid),
               v.판정, g.hhld_cnt_sum, g.complex_nm, v.s, v.kapt_name, v.세대
          FROM #v v JOIN #g g ON g.kapt_code = v.kapt_code WHERE v.판정 = N'묶음';
    COMMIT;
    SELECT j = (SELECT
        K후보 = (SELECT COUNT(*) FROM #k), C0하나 = (SELECT COUNT(*) FROM #k0),
        판정 = (SELECT 판정, n = COUNT(*), 세대 = SUM(세대) FROM #v GROUP BY 판정 FOR JSON PATH), 번호하나이하 = (SELECT COUNT(*) FROM #ks),
        묶음 = (SELECT TOP 60 v.kapt_name, v.세대, v.조각, 조각들 = (SELECT STRING_AGG(CAST(g.cid AS VARCHAR(10)) + ':' + CAST(g.hhld_cnt_sum AS VARCHAR(10)), ' + ') FROM #g g WHERE g.kapt_code = v.kapt_code), v.kapt_usedate
                  FROM #v v WHERE v.판정 = N'묶음' ORDER BY v.세대 DESC FOR JSON PATH),
        세대다름보기 = (SELECT TOP 15 v.kapt_name, v.세대, v.합, v.조각 FROM #v v WHERE v.판정 = N'세대다름' ORDER BY v.세대 DESC FOR JSON PATH),
        조각하나보기 = (SELECT TOP 10 v.kapt_name, v.세대, v.합 FROM #v v WHERE v.판정 = N'조각하나' ORDER BY v.세대 DESC FOR JSON PATH)
      FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
END
GO
EXEC gold.usp_plan_merge_kapt;
GO
