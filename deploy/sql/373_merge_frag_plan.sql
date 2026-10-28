/* ============================================================
   373_merge_frag_plan : 총괄표제부 없이 동마다 따로 된 대장 조각을 **대장 칸만으로** 묶는 계획 (2026-10-28 사장님 "A ㄱㄱ")
   사장님: "다른 시스템(국토부 aptSeq)에 종속되는 게 별로 — 국토부가 묶은 케이스를 살펴봐서 대표지번 · 부속지번 같은 걸로"
   → 국토부 묶음을 **채점용 정답**으로만 써서 잰 규칙(_p_frag3/5/6):
      같은 필지(또는 부속지번으로 이어짐) + (허가일 같음 또는 도로명주소[도로코드+건물본번] 같음)
      = 국토부 한 단지 조각 짝의 97.3% · 300m 안 다른 단지 짝 29.8만 중 36 (차수 나눠 지은 곳 1차·2차는 하나로 보일 수 있음 — 사장님 A 선택)
   ★ 대상: 주용도 '공동주택' 동(세대 있음)이 있는 단지 조각만 — 국토부 아파트로 잰 규칙이라 다가구 · 단독은 넣지 않는다(신도림동 작은 집 둘이 묶일 뻔했다).
   ★ 안전장치(빼기만 함): 덩어리 안에 서로 다른 K-apt 단지가 둘 이상 · 대장 건물명이 서로 다름(동 꼬리 · 주소꼴 이름은 같은 것으로) → '보류'.
   ★ 덩어리가 너무 크거나(조각 80 넘음) 넓으면(1km 넘게 퍼짐) 묶지 않고 '보류' — 부속지번이 도로 · 공원 필지라 줄줄이 이어지는 것을 막는다.
   ★ 남는 코드 = 세대 많은 조각(같으면 번호 작은 것). 이름은 안 본다.
   ★ 적용은 374(287 · 331 과 같은 방법 — 지우지 않음 · 기록 · 되돌리기 가능).
   ============================================================ */
SET QUOTED_IDENTIFIER ON; SET ANSI_NULLS ON;
GO
IF OBJECT_ID('ops.complex_merge_plan_frag') IS NULL
CREATE TABLE ops.complex_merge_plan_frag (
    complex_id INT NOT NULL CONSTRAINT pk_complex_merge_plan_frag PRIMARY KEY,
    남을코드   INT NOT NULL,
    묶음조각   INT NOT NULL,
    이름       NVARCHAR(200) NULL,
    세대       INT NULL,
    판정       NVARCHAR(10) NOT NULL,      -- 묶음 | 보류
    근거       NVARCHAR(200) NOT NULL,
    at         DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()
);
GO
CREATE OR ALTER PROCEDURE gold.usp_plan_merge_frag
AS
BEGIN
    SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    IF OBJECT_ID('tempdb..#n') IS NOT NULL DROP TABLE #n;
    SELECT c.complex_id, hh = SUM(ISNULL(t.hhld_cnt, 0)), lat = CAST(MAX(c.centroid_lat) AS FLOAT), lng = CAST(MAX(c.centroid_lng) AS FLOAT)
      INTO #n FROM gold.complex c
      JOIN gold.complex_bld cb ON cb.complex_id = c.complex_id
      JOIN silver.bld_title t ON t.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND t.is_current = 1 AND t.main_purps_nm = N'공동주택'
     WHERE c.merged_into IS NULL AND c.is_active = 1
     GROUP BY c.complex_id HAVING SUM(ISNULL(t.hhld_cnt, 0)) > 0;
    CREATE CLUSTERED INDEX x ON #n (complex_id);
    IF OBJECT_ID('tempdb..#np') IS NOT NULL DROP TABLE #np;
    SELECT DISTINCT cp.complex_id, cp.pnu INTO #np FROM gold.complex_pnu cp JOIN #n n ON n.complex_id = cp.complex_id;
    CREATE CLUSTERED INDEX x ON #np (pnu, complex_id);
    IF OBJECT_ID('tempdb..#na') IS NOT NULL DROP TABLE #na;
    SELECT DISTINCT cb.complex_id, a.atch_pnu INTO #na FROM gold.complex_bld cb JOIN #n n ON n.complex_id = cb.complex_id
      JOIN silver.bld_atch_jibun a ON a.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND a.is_current = 1 WHERE a.atch_pnu IS NOT NULL;
    CREATE CLUSTERED INDEX x ON #na (atch_pnu, complex_id);
    IF OBJECT_ID('tempdb..#nf') IS NOT NULL DROP TABLE #nf;
    SELECT DISTINCT cb.complex_id, k = CAST(CONCAT('P', t.pms_day) AS VARCHAR(40)) INTO #nf FROM gold.complex_bld cb JOIN #n n ON n.complex_id = cb.complex_id
      JOIN silver.bld_title t ON t.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND t.is_current = 1 AND t.main_purps_nm = N'공동주택' WHERE LEN(t.pms_day) = 8;
    INSERT #nf SELECT DISTINCT cb.complex_id, CONCAT('R', t.na_road_cd, '-', TRY_CAST(t.na_main_bun AS INT)) FROM gold.complex_bld cb JOIN #n n ON n.complex_id = cb.complex_id
      JOIN silver.bld_title t ON t.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND t.is_current = 1 AND t.main_purps_nm = N'공동주택'
     WHERE t.na_road_cd IS NOT NULL AND TRY_CAST(t.na_main_bun AS INT) > 0;
    CREATE CLUSTERED INDEX x ON #nf (complex_id, k);
    /* 후보 짝: 같은 필지 · 부속지번이 상대 필지 · 같은 부속지번(30곳 넘게 쓰는 부속지번은 도로 · 공원일 수 있어 뺌) */
    IF OBJECT_ID('tempdb..#pr') IS NOT NULL DROP TABLE #pr;
    CREATE TABLE #pr (a INT NOT NULL, b INT NOT NULL, 길 CHAR(1) NOT NULL);
    INSERT #pr SELECT DISTINCT x.complex_id, y.complex_id, 'S' FROM #np x JOIN #np y ON y.pnu = x.pnu AND y.complex_id > x.complex_id;
    INSERT #pr SELECT DISTINCT CASE WHEN x.complex_id < y.complex_id THEN x.complex_id ELSE y.complex_id END,
                               CASE WHEN x.complex_id < y.complex_id THEN y.complex_id ELSE x.complex_id END, 'A'
      FROM #na x JOIN #np y ON y.pnu = x.atch_pnu AND y.complex_id <> x.complex_id;
    INSERT #pr SELECT DISTINCT x.complex_id, y.complex_id, 'C' FROM #na x JOIN #na y ON y.atch_pnu = x.atch_pnu AND y.complex_id > x.complex_id
     WHERE x.atch_pnu IN (SELECT atch_pnu FROM #na GROUP BY atch_pnu HAVING COUNT(*) <= 30);
    IF OBJECT_ID('tempdb..#e') IS NOT NULL DROP TABLE #e;
    SELECT DISTINCT p.a, p.b INTO #e FROM #pr p
     WHERE EXISTS (SELECT 1 FROM #nf x JOIN #nf y ON y.k = x.k WHERE x.complex_id = p.a AND y.complex_id = p.b);
    INSERT #e SELECT b, a FROM #e;
    CREATE CLUSTERED INDEX x ON #e (a, b);
    /* 덩어리 = 이어진 것끼리(가장 작은 번호로 번져 나감) */
    IF OBJECT_ID('tempdb..#g') IS NOT NULL DROP TABLE #g;
    SELECT DISTINCT a AS complex_id, g = a INTO #g FROM #e;
    CREATE CLUSTERED INDEX x ON #g (complex_id);
    DECLARE @ch INT = 1, @i INT = 0;
    WHILE @ch > 0 AND @i < 60
    BEGIN
        UPDATE g SET g = z.m FROM #g g JOIN (SELECT e.a, m = MIN(gb.g) FROM #e e JOIN #g gb ON gb.complex_id = e.b GROUP BY e.a) z ON z.a = g.complex_id WHERE z.m < g.g;
        SET @ch = @@ROWCOUNT; SET @i += 1;
    END
    IF OBJECT_ID('tempdb..#s') IS NOT NULL DROP TABLE #s;
    SELECT g.g, 조각 = COUNT(*), 퍼짐 = (MAX(n.lat) - MIN(n.lat)) * 111000 + (MAX(n.lng) - MIN(n.lng)) * 88000,
           남을 = (SELECT TOP 1 g2.complex_id FROM #g g2 JOIN #n n2 ON n2.complex_id = g2.complex_id WHERE g2.g = g.g ORDER BY n2.hh DESC, g2.complex_id)
      INTO #s FROM #g g JOIN #n n ON n.complex_id = g.complex_id GROUP BY g.g;
    /* 안전장치: 덩어리 안에 **서로 다른 K-apt 단지**가 둘 이상 이어져 있으면 묶지 않는다(K-apt 가 다른 단지로 관리 = 다른 단지) */
    ALTER TABLE #s ADD kapt INT NULL;
    UPDATE s SET kapt = z.n FROM #s s JOIN (SELECT g.g, n = COUNT(DISTINCT k.kapt_code) FROM #g g JOIN gold.complex_kapt k ON k.complex_id = g.complex_id GROUP BY g.g) z ON z.g = s.g;
    /* 안전장치 2: 대장 건물명이 서로 다르면 묶지 않는다 — 이름으로 **잇지는 않는다**(묶음의 근거는 필지 · 허가일 · 도로명뿐), 다르면 **빼기만** 한다.
       '… 106동' · '… B동' 같은 동 꼬리, 주소꼴('…번지') · '공동주택' 같은 빈 이름은 다름으로 치지 않는다(이동우방파크빌 / 이동 현대 홈타운이 묶일 뻔했다). */
    ALTER TABLE #s ADD 이름수 INT NULL;
    UPDATE s SET 이름수 = z.n FROM #s s JOIN (
        SELECT x.g, n = COUNT(DISTINCT x.b) FROM (
            SELECT g.g, b = REPLACE(CASE WHEN RIGHT(m.n0, 1) = N'동' AND CHARINDEX(' ', REVERSE(m.n0)) BETWEEN 2 AND 6
                                          THEN LEFT(m.n0, LEN(m.n0) - CHARINDEX(' ', REVERSE(m.n0))) ELSE m.n0 END, ' ', '')
              FROM #g g JOIN gold.complex c ON c.complex_id = g.complex_id
             CROSS APPLY (SELECT n0 = LTRIM(RTRIM(ISNULL(c.complex_nm, N'')))) m
             WHERE m.n0 NOT LIKE N'%번지' AND m.n0 NOT IN (N'공동주택', N'주택', N'아파트', N'연립주택', N'다세대주택') AND m.n0 <> N'') x
         GROUP BY x.g) z ON z.g = s.g;
    TRUNCATE TABLE ops.complex_merge_plan_frag;   -- 계획표(다시 만드는 표) — 적용 기록은 ops.complex_merged 에 따로 남는다
    INSERT ops.complex_merge_plan_frag (complex_id, 남을코드, 묶음조각, 이름, 세대, 판정, 근거)
    SELECT g.complex_id, s.남을, s.조각, c.complex_nm, n.hh,
           CASE WHEN s.조각 > 80 OR s.퍼짐 > 1000 OR s.kapt > 1 OR s.이름수 > 1 THEN N'보류' ELSE N'묶음' END,
           LEFT(CONCAT(N'373 같은 필지/부속지번 + 같은 허가일/도로명 · 조각 ', s.조각, N' · 퍼짐 ', CAST(s.퍼짐 AS INT), N'm', CASE WHEN s.kapt > 1 THEN N' · K-apt 단지 여럿' ELSE N'' END, CASE WHEN s.이름수 > 1 THEN N' · 대장 건물명 여럿' ELSE N'' END), 200)
      FROM #g g JOIN #s s ON s.g = g.g JOIN #n n ON n.complex_id = g.complex_id JOIN gold.complex c ON c.complex_id = g.complex_id;
    SELECT 덩어리 = COUNT(*), 조각 = SUM(조각), 흡수될조각 = SUM(조각) - COUNT(*),
           묶음덩어리 = SUM(CASE WHEN 조각 <= 80 AND 퍼짐 <= 1000 AND ISNULL(kapt, 0) <= 1 AND ISNULL(이름수, 0) <= 1 THEN 1 ELSE 0 END),
           보류덩어리 = SUM(CASE WHEN 조각 > 80 OR 퍼짐 > 1000 OR kapt > 1 OR 이름수 > 1 THEN 1 ELSE 0 END),
           조각2 = SUM(CASE WHEN 조각 = 2 THEN 1 ELSE 0 END), 조각3_9 = SUM(CASE WHEN 조각 BETWEEN 3 AND 9 THEN 1 ELSE 0 END),
           조각10_ = SUM(CASE WHEN 조각 >= 10 THEN 1 ELSE 0 END), 최대 = MAX(조각), 되풀이 = @i
      FROM #s;
END
GO
EXEC gold.usp_plan_merge_frag;
GO
SELECT TOP 15 p.남을코드, 이름 = MAX(CASE WHEN p.complex_id = p.남을코드 THEN p.이름 END), 조각 = MAX(p.묶음조각), 세대합 = SUM(p.세대), 판정 = MAX(p.판정), 근거 = MAX(p.근거),
       이름가짓수 = COUNT(DISTINCT p.이름)
  FROM ops.complex_merge_plan_frag p GROUP BY p.남을코드 ORDER BY MAX(p.묶음조각) DESC;
SELECT TOP 15 p.남을코드, 이름들 = STRING_AGG(CAST(p.이름 AS NVARCHAR(MAX)), N' / '), 조각 = MAX(p.묶음조각), 판정 = MAX(p.판정)
  FROM ops.complex_merge_plan_frag p
 WHERE p.판정 = N'묶음' AND p.남을코드 IN (SELECT 남을코드 FROM ops.complex_merge_plan_frag GROUP BY 남을코드 HAVING COUNT(DISTINCT 이름) > 1)
 GROUP BY p.남을코드 ORDER BY NEWID();
SELECT TOP 12 남을코드, 이름들 = STRING_AGG(CAST(이름 AS NVARCHAR(MAX)), N' / '), 근거 = MAX(근거) FROM ops.complex_merge_plan_frag WHERE 판정 = N'보류' AND 근거 LIKE N'%건물명%' GROUP BY 남을코드 ORDER BY NEWID();
SELECT 시대아파트 = COUNT(*), 남을 = MAX(남을코드), 판정 = MAX(판정) FROM ops.complex_merge_plan_frag WHERE complex_id BETWEEN 722419 AND 722429;
SELECT 판정, 덩어리 = COUNT(DISTINCT 남을코드), 조각 = COUNT(*), 이름여럿덩어리 = (SELECT COUNT(*) FROM (SELECT 남을코드 FROM ops.complex_merge_plan_frag q WHERE q.판정 = p.판정 GROUP BY 남을코드 HAVING COUNT(DISTINCT 이름) > 1) z)
  FROM ops.complex_merge_plan_frag p GROUP BY 판정;
