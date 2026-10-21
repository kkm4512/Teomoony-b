/* ============================================================
   286_merge_plan : 쪼개진 단지 조각을 하나로 묶는 **계획만** 만든다 (2026-10-21, 사장님 "ㄱㄱ")
   ★ 아무 단지도 바꾸지 않는다. ops.complex_merge_plan 에 계획을 적고 요약을 보여 준다.
     적용(287)은 사장님이 이 결과를 본 뒤에.

   ★ 왜: 단지를 대장 총괄표제부(root) 로 묶는데, 오래된 대단지는 대장이 여러 root 로 등록돼
     한 단지가 여러 조각이 된다 — 중계그린 878 + 1,675 · 창동주공3 230 + 2,627 · 한가람 18조각.

   ★ 묶는 규칙 — 근거 둘이 다 맞을 때만
     ① 같은 필지(PNU)를 쓰는 **주거 조각끼리** — 주용도가 주택인 동의 세대가 있고 그 조각 세대의 절반 이상.
        주민센터·교회·어린이집은 물론, 대장 세대수 칸이 차 있는 상가·시장·숙박도 안 넣는다.
        단, 그 필지가 **본번 0(지번 모름)** 이거나 **산 지번**이면 근거로 안 쓴다
        (세곡동 0번지 78 · 고덕동 0번지 41 · 홍은동 산1-8 81 이 한 덩어리가 된다).
     ② 두 조각의 모든 필지에 붙은 아파트 실거래의 **국토부 단지번호(apt_seq)가 합쳐서 정확히 하나**.
        둘 이상이면 실제로 다른 단지(묶지 않음 = '번호여럿'), 0 이면 근거 없음(묶지 않음 = '근거없음').
     ③ 이어지는 묶음(A-B, B-C)은 한 묶음. **20 조각 넘으면 묶지 않고 '너무큼'** 으로 둔다.
     남는 코드 = 세대 가장 많은 조각(같으면 코드 작은 쪽).
   ============================================================ */
SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
GO
IF OBJECT_ID('ops.complex_merge_plan') IS NULL
CREATE TABLE ops.complex_merge_plan (
    묶음        INT           NOT NULL,
    complex_id  INT           NOT NULL,
    남을코드    INT           NULL,
    판정        NVARCHAR(20)  NOT NULL,     -- 묶음 | 번호여럿 | 근거없음 | 너무큼
    세대        INT           NULL,
    이름        NVARCHAR(200) NULL,
    단지번호    NVARCHAR(200) NULL,
    만든시각    DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_complex_merge_plan PRIMARY KEY (complex_id)
);
GO
SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DELETE FROM ops.complex_merge_plan;     -- 계획표(파생)는 매번 새로 만든다

/* ★ 18:05: 주거 조각 = **주용도가 주택인 동의 세대**가 있고, 그게 그 조각 세대의 절반 이상.
   대장 세대수 칸이 상가·시장·숙박에도 차 있다(잠실파인애플상가 489 · 로담코인사빌딩 213). */
IF OBJECT_ID('tempdb..#res') IS NOT NULL DROP TABLE #res;
SELECT c.complex_id, 주택세대 = SUM(ISNULL(t.hhld_cnt, 0)), 세대 = MAX(c.hhld_cnt_sum) INTO #res
  FROM gold.complex c JOIN gold.complex_bld cb ON cb.complex_id = c.complex_id
  JOIN silver.bld_title t ON t.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND t.is_current = 1
 WHERE c.hhld_cnt_sum > 0 AND t.main_purps_nm LIKE N'%주택%'
   AND c.complex_id IN (SELECT complex_id FROM gold.complex_pnu WHERE pnu IN (SELECT pnu FROM gold.complex_pnu GROUP BY pnu HAVING COUNT(*) > 1))
 GROUP BY c.complex_id
HAVING SUM(ISNULL(t.hhld_cnt, 0)) > 0 AND SUM(ISNULL(t.hhld_cnt, 0)) * 2 >= MAX(c.hhld_cnt_sum);
CREATE CLUSTERED INDEX x ON #res (complex_id);

/* 근거로 쓸 수 있는 공유 필지 */
IF OBJECT_ID('tempdb..#sp') IS NOT NULL DROP TABLE #sp;
SELECT cp.pnu INTO #sp
  FROM gold.complex_pnu cp JOIN #res c ON c.complex_id = cp.complex_id
 WHERE SUBSTRING(cp.pnu, 11, 1) = '1' AND SUBSTRING(cp.pnu, 12, 4) <> '0000'
 GROUP BY cp.pnu HAVING COUNT(*) > 1;
CREATE CLUSTERED INDEX x ON #sp (pnu);

/* 걸린 조각들 */
IF OBJECT_ID('tempdb..#pc') IS NOT NULL DROP TABLE #pc;
SELECT DISTINCT cp.complex_id INTO #pc
  FROM gold.complex_pnu cp JOIN #sp s ON s.pnu = cp.pnu
  JOIN #res c ON c.complex_id = cp.complex_id;
CREATE CLUSTERED INDEX x ON #pc (complex_id);

/* 조각마다 단지번호 — 그 조각의 (지번 아는) 필지에 붙은 아파트 실거래 */
IF OBJECT_ID('tempdb..#seq') IS NOT NULL DROP TABLE #seq;
SELECT DISTINCT cp.complex_id, t.apt_seq INTO #seq
  FROM #pc p JOIN gold.complex_pnu cp ON cp.complex_id = p.complex_id
  JOIN silver.rtms_trade t ON t.match_pnu = cp.pnu
 WHERE t.trade_kind LIKE 'APT%' AND t.apt_seq IS NOT NULL
   AND SUBSTRING(cp.pnu, 11, 1) = '1' AND SUBSTRING(cp.pnu, 12, 4) <> '0000';

/* 짝(양방향) — 같은 공유 필지의 세대 있는 두 조각 */
IF OBJECT_ID('tempdb..#pair') IS NOT NULL DROP TABLE #pair;
SELECT DISTINCT a = x.complex_id, b = y.complex_id INTO #pair
  FROM #sp s
  JOIN gold.complex_pnu x ON x.pnu = s.pnu JOIN #pc px ON px.complex_id = x.complex_id
  JOIN gold.complex_pnu y ON y.pnu = s.pnu JOIN #pc py ON py.complex_id = y.complex_id
 WHERE x.complex_id <> y.complex_id;

/* 짝마다 판정 */
IF OBJECT_ID('tempdb..#e') IS NOT NULL DROP TABLE #e;
SELECT p.a, p.b,
       번호수 = (SELECT COUNT(DISTINCT q.apt_seq) FROM #seq q WHERE q.complex_id IN (p.a, p.b))
  INTO #e FROM #pair p;

/* 묶을 짝만으로 이어 붙인다(최소 코드 전파) */
IF OBJECT_ID('tempdb..#l') IS NOT NULL DROP TABLE #l;
SELECT complex_id, lab = complex_id INTO #l FROM #pc;
CREATE CLUSTERED INDEX x ON #l (complex_id);
DECLARE @n INT = 1, @돌기 INT = 0;
WHILE @n > 0 AND @돌기 < 50
BEGIN
    UPDATE l SET lab = m.mn
      FROM #l l JOIN (SELECT e.a, mn = MIN(l2.lab) FROM #e e JOIN #l l2 ON l2.complex_id = e.b
                       WHERE e.번호수 = 1 GROUP BY e.a) m ON m.a = l.complex_id
     WHERE m.mn < l.lab;
    SET @n = @@ROWCOUNT; SET @돌기 += 1;
END

;WITH g AS (
    SELECT l.complex_id, l.lab, c.hhld_cnt_sum, c.complex_nm,
           조각수 = COUNT(*) OVER (PARTITION BY l.lab),
           rn = ROW_NUMBER() OVER (PARTITION BY l.lab ORDER BY c.hhld_cnt_sum DESC, l.complex_id)
      FROM #l l JOIN gold.complex c ON c.complex_id = l.complex_id)
INSERT INTO ops.complex_merge_plan (묶음, complex_id, 남을코드, 판정, 세대, 이름, 단지번호)
SELECT g.lab, g.complex_id,
       남을코드 = CASE WHEN g.조각수 BETWEEN 2 AND 20 THEN (SELECT g2.complex_id FROM g g2 WHERE g2.lab = g.lab AND g2.rn = 1) END,
       판정 = CASE WHEN g.조각수 > 20 THEN N'너무큼'
                   WHEN g.조각수 >= 2 THEN N'묶음'
                   WHEN EXISTS (SELECT 1 FROM #e e WHERE e.a = g.complex_id AND e.번호수 >= 2) THEN N'번호여럿'
                   ELSE N'근거없음' END,
       g.hhld_cnt_sum, g.complex_nm,
       (SELECT STRING_AGG(q.apt_seq, ',') FROM #seq q WHERE q.complex_id = g.complex_id)
  FROM g;
GO
SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT j = (SELECT
   조각 = COUNT(*),
   묶이는조각 = SUM(CASE WHEN 판정 = N'묶음' THEN 1 ELSE 0 END),
   묶음수 = COUNT(DISTINCT CASE WHEN 판정 = N'묶음' THEN 묶음 END),
   사라질코드 = SUM(CASE WHEN 판정 = N'묶음' AND complex_id <> 남을코드 THEN 1 ELSE 0 END),
   번호여럿 = SUM(CASE WHEN 판정 = N'번호여럿' THEN 1 ELSE 0 END),
   근거없음 = SUM(CASE WHEN 판정 = N'근거없음' THEN 1 ELSE 0 END),
   너무큼 = SUM(CASE WHEN 판정 = N'너무큼' THEN 1 ELSE 0 END)
  FROM ops.complex_merge_plan FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
GO
