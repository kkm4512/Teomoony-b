/* 396_bdong_succ : 법정동 이름 · 옛 코드 → 지금 코드 (2026-10-31 사장님 "법정동·행정동이 분리·통합됐을 때 골치 아픈 상황 방지")
   ★ 원본 자료(대장 · 인허가 · 단지 · 상가 …)의 코드는 그대로 둔다. 여기서는 '이 코드의 이름' 과 '옛 코드 → 지금 코드' 만 만든다.
   ★ 근거는 공식 자료뿐 — 이름으로 잇지 않는다.
       ① 행안부 법정동 코드 이력(silver.mois_bdong_code, 395 · 말소코드 포함판): 말소일자 · 생성일자
       ② 지금 지적(silver.cadastral_parcel, is_current = 1): 옛 PNU 의 지번(산 · 본번 · 부번)이 지금 어느 코드 아래 있나
   ★ 옛 → 지금 은 **확실한 것만** 적는다(2026-10-31 시험 공간 실측):
       후보 = 옛 코드 말소일에 생긴 코드 중 (가) 같은 시군구이거나 (나) 옛 시군구가 그날 말소되고 새 시군구가 그날 생긴 곳
              (시도가 달라지면 옛 시도도 그날 말소됐을 때만 — 강원 · 전북 특별자치도 · 전남광주 통합 · 군위 대구 편입).
              새 코드가 그 뒤 또 말소됐으면 같은 규칙으로 따라간다(최대 3번).
       확정 = 우리 자료에 나온 옛 코드의 PNU 가 **3개 이상**이고, 그 **전부**의 지번이 지금 필지로 있는 후보가 **딱 하나**일 때.
              단 3~4필지는 리 번호가 그대로이거나(면→읍 승격) 시군구째 바뀐 경우만.
       그 밖(후보 여럿 · 갈림 · 기존 동에 흡수 · 필지 1~2개)은 적지 않는다 — 화면은 옛 이름 + 폐지일로 보인다.
       실측: 우리 자료의 말소 코드 1,191개 중 확정 60개. 날짜 · 지번만으로는 더 못 정한다(같은 날 같은 시군구에 새 코드가 수십 개,
       '1번지' 는 어느 동에나 있다). 더 이으려면 필지별 행정구역 변경 기록(토지이동이력 전국 파일)이 있어야 한다.
   ★ 단지는 위치로 따로 잇는다(gold.complex_lawd_now): 단지 중심점이 든 지금 필지의 코드 — 지역 묶음(/r)은 이걸 먼저 쓴다.
     (검단신도시처럼 '블록' 주소라 지번이 없는 곳도 위치로는 안다) */
SET NOCOUNT ON;
GO
CREATE OR ALTER VIEW gold.v_bdong_code AS
/* 행안부 이력 가장 최근 판 — 현행 + 말소. 이름은 원문 그대로 */
SELECT b.법정동코드, b.시도명, b.시군구명, b.읍면동명, b.동리명, b.생성일자, b.말소일자,
       현행 = CAST(CASE WHEN b.말소일자 IS NULL THEN 1 ELSE 0 END AS BIT), b.판
  FROM silver.mois_bdong_code b
 WHERE b.판 = (SELECT MAX(판) FROM silver.mois_bdong_code);
GO
IF OBJECT_ID('gold.bdong_succ_code') IS NULL
CREATE TABLE gold.bdong_succ_code (
    옛코드    CHAR(10)     NOT NULL PRIMARY KEY,
    새코드    CHAR(10)     NOT NULL,
    말소일자  CHAR(8)      NULL,
    필지수    INT          NOT NULL,     -- 근거가 된 옛 PNU 수(전부 새 코드 아래 같은 지번으로 있음)
    규칙      VARCHAR(10)  NOT NULL,     -- a 같은 시군구 · b 시군구 바뀜 · …c 그 뒤 또 바뀜
    만든때    DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()
);
GO
IF OBJECT_ID('gold.complex_lawd_now') IS NULL
CREATE TABLE gold.complex_lawd_now (
    complex_id  INT          NOT NULL PRIMARY KEY,
    옛코드      CHAR(10)     NOT NULL,     -- 단지 대표 PNU 의 코드(원본 그대로) — 행안부 현행이 아님
    지금코드    CHAR(10)     NOT NULL,     -- 단지 중심점이 든 지금 필지의 코드
    근거pnu     CHAR(19)     NOT NULL,     -- 그 지금 필지
    만든때      DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()
);
GO
CREATE OR ALTER PROCEDURE gold.usp_build_bdong_succ AS
BEGIN
    SET NOCOUNT ON;
    /* 1 우리 자료의 옛 PNU — 코드가 행안부 현행이 아닌 줄 (현행 코드를 먼저 임시표로 — 뷰를 줄마다 부르면 느리다) */
    SELECT 법정동코드 INTO #현행 FROM gold.v_bdong_code WHERE 현행 = 1;
    CREATE UNIQUE CLUSTERED INDEX c ON #현행 (법정동코드);
    CREATE TABLE #옛 (pnu CHAR(19) NOT NULL PRIMARY KEY);
    INSERT #옛 SELECT DISTINCT p FROM (
        SELECT p = rep_pnu FROM gold.complex
        UNION ALL SELECT pnu FROM silver.bld_title WHERE is_current = 1
        UNION ALL SELECT pnu FROM silver.bld_closed_title
        UNION ALL SELECT pnu FROM silver.arch_permit
        UNION ALL SELECT pnu FROM silver.kapt_complex
        UNION ALL SELECT pnu FROM silver.semas_store) z
     WHERE p LIKE '[0-9]%' AND LEN(p) = 19
       AND NOT EXISTS (SELECT 1 FROM #현행 b WHERE b.법정동코드 = LEFT(z.p, 10));

    SELECT 법정동코드, 생성일자, 말소일자 INTO #B FROM gold.v_bdong_code;
    CREATE CLUSTERED INDEX c ON #B (법정동코드);
    SELECT DISTINCT 시도 = LEFT(법정동코드, 2), 생성일자 INTO #새시군구 FROM #B WHERE 법정동코드 LIKE '_____00000' AND 법정동코드 NOT LIKE '__00000000';

    /* 2 코드 후보 */
    SELECT DISTINCT 옛코드 = x.법정동코드, x.말소일자, 새코드 = y.법정동코드,
           규칙 = CAST(CASE WHEN LEFT(y.법정동코드, 5) = LEFT(x.법정동코드, 5) THEN 'a' ELSE 'b' END AS VARCHAR(10))
      INTO #k
      FROM #B x
      JOIN #B y ON y.생성일자 = x.말소일자 AND SUBSTRING(y.법정동코드, 6, 3) <> '000'
      LEFT JOIN #B xs ON xs.법정동코드 = LEFT(x.법정동코드, 5) + '00000'
      LEFT JOIN #B ys ON ys.법정동코드 = LEFT(y.법정동코드, 5) + '00000'
      LEFT JOIN #B xd ON xd.법정동코드 = LEFT(x.법정동코드, 2) + '00000000'
      LEFT JOIN #새시군구 ns ON ns.시도 = LEFT(x.법정동코드, 2) AND ns.생성일자 = x.말소일자
     WHERE x.말소일자 IS NOT NULL AND x.법정동코드 IN (SELECT LEFT(pnu, 10) FROM #옛)
       AND (LEFT(y.법정동코드, 5) = LEFT(x.법정동코드, 5)
            OR (xs.말소일자 = x.말소일자 AND ys.생성일자 = x.말소일자
                AND (LEFT(y.법정동코드, 2) = LEFT(x.법정동코드, 2)          -- 같은 시도 안에서 시군구가 바뀜(검단구 신설)
                     OR xd.말소일자 = x.말소일자                           -- 시도째 바뀜(특별자치도 · 전남광주 통합)
                     OR ns.시도 IS NULL)));                                -- 시군구가 다른 시도로 옮김(군위): 옛 시도에 그날 새 시군구가 없을 때만
    DECLARE @i INT = 0;
    WHILE @i < 3
    BEGIN
        INSERT #k
        SELECT DISTINCT k.옛코드, k.말소일자, y.법정동코드, k.규칙 + 'c'
          FROM #k k
          JOIN #B m ON m.법정동코드 = k.새코드 AND m.말소일자 IS NOT NULL
          JOIN #B y ON y.생성일자 = m.말소일자 AND SUBSTRING(y.법정동코드, 6, 3) <> '000' AND LEFT(y.법정동코드, 5) = LEFT(m.법정동코드, 5)
         WHERE NOT EXISTS (SELECT 1 FROM #k z WHERE z.옛코드 = k.옛코드 AND z.새코드 = y.법정동코드);
        SET @i += 1;
    END

    /* 3 지번 대조 — 지금 필지는 PNU 로 바로 찾는다(새코드 + 옛 지번) */
    SELECT DISTINCT o.pnu, k.새코드, k.규칙, 새pnu = CAST(k.새코드 + RIGHT(o.pnu, 9) AS CHAR(19)) INTO #c
      FROM #옛 o
      JOIN #k k ON k.옛코드 = LEFT(o.pnu, 10)
      JOIN #B y ON y.법정동코드 = k.새코드 AND y.말소일자 IS NULL;
    CREATE CLUSTERED INDEX c ON #c (새pnu);
    SELECT c.pnu, c.새코드, c.규칙 INTO #h
      FROM #c c WHERE EXISTS (SELECT 1 FROM silver.cadastral_parcel p WHERE p.pnu = c.새pnu AND p.is_current = 1);

    /* 4 확정: 옛 PNU 3개 이상 · 전부 맞는 후보가 딱 하나 */
    WITH n AS (SELECT 옛코드 = LEFT(pnu, 10), n = COUNT(*) FROM #옛 GROUP BY LEFT(pnu, 10)),
         s AS (SELECT 옛코드 = LEFT(pnu, 10), 새코드, 규칙 = MIN(규칙), sc = COUNT(DISTINCT pnu) FROM #h GROUP BY LEFT(pnu, 10), 새코드),
         t AS (SELECT s.*, n.n, 전부 = SUM(CASE WHEN s.sc = n.n THEN 1 ELSE 0 END) OVER (PARTITION BY s.옛코드)
                 FROM s JOIN n ON n.옛코드 = s.옛코드)
    SELECT 옛코드, 새코드, 필지수 = n, 규칙 INTO #확정 FROM t
     WHERE 전부 = 1 AND sc = n AND n >= 3
       AND (n >= 5 OR 규칙 LIKE 'b%' OR (RIGHT(옛코드, 2) <> '00' AND RIGHT(옛코드, 2) = RIGHT(새코드, 2)));
       /* 필지 3~4개로만 맞은 것은 '리 번호가 그대로(면→읍)' 거나 시군구째 바뀐 경우만 — 우연히 지번 몇 개가 겹친 것을 막는다
          (실측: 교하읍 신촌리 3필지가 오도동에 다 있었지만 택지 환지로 지번이 다시 매겨진 곳이라 믿을 수 없음) */

    /* 5 단지는 위치로도 — 대표 PNU 코드가 현행이 아닌 단지: 중심점이 든 지금 필지(지적 도형, SRID 4326)의 코드.
         코드 단위 확정(4)이 없어도 단지 하나하나는 지금 어느 동에 있는지 안다. 필지 하나에만 들 때만 적는다. */
    SELECT c.complex_id, 옛코드 = LEFT(c.rep_pnu, 10), 지금코드 = LEFT(p.pnu, 10), 근거pnu = p.pnu,
           n = COUNT(*) OVER (PARTITION BY c.complex_id)
      INTO #위치
      FROM gold.complex c
      JOIN silver.cadastral_parcel p ON p.is_current = 1 AND p.geom IS NOT NULL
       AND p.geom.STIntersects(geometry::Point(c.centroid_lng, c.centroid_lat, 4326)) = 1
     WHERE c.is_active = 1 AND c.centroid_lat IS NOT NULL AND c.centroid_lng IS NOT NULL AND LEN(c.rep_pnu) = 19
       AND NOT EXISTS (SELECT 1 FROM #현행 b WHERE b.법정동코드 = LEFT(c.rep_pnu, 10));

    BEGIN TRAN;
    DELETE FROM gold.complex_lawd_now;
    INSERT gold.complex_lawd_now (complex_id, 옛코드, 지금코드, 근거pnu)
    SELECT w.complex_id, w.옛코드, w.지금코드, w.근거pnu FROM #위치 w
     WHERE w.n = 1 AND EXISTS (SELECT 1 FROM #현행 b WHERE b.법정동코드 = w.지금코드);
    DELETE FROM gold.bdong_succ_code;
    INSERT gold.bdong_succ_code (옛코드, 새코드, 말소일자, 필지수, 규칙)
    SELECT f.옛코드, f.새코드, b.말소일자, f.필지수, f.규칙 FROM #확정 f JOIN #B b ON b.법정동코드 = f.옛코드;
    COMMIT;
    SELECT 옛코드 = (SELECT COUNT(DISTINCT LEFT(pnu, 10)) FROM #옛), 확정 = (SELECT COUNT(*) FROM #확정),
           단지위치 = (SELECT COUNT(*) FROM gold.complex_lawd_now);
END
GO
CREATE OR ALTER VIEW gold.v_lawd_name AS
/* 법정동 코드 → 이름. 사전(meta.lawd_code, 현행)에 있으면 그대로, 없으면 행안부 이력(말소 포함)에서.
   지금코드 = 현행이면 자기 자신, 말소면 확정 대응(gold.bdong_succ_code)이 있을 때만.
   표시 = 화면에 그대로 쓰는 이름 — 말소면 '옛 ' + 이름 + ' (YYYY.MM.DD 폐지)'. */
SELECT lawd_cd = l.lawd_cd, l.sido_nm, l.sgg_nm, l.emd_nm, l.ri_nm, l.full_nm,
       현행 = CAST(CASE WHEN l.is_abolished = 0 THEN 1 ELSE 0 END AS BIT), 말소일자 = b.말소일자,
       지금코드 = CASE WHEN l.is_abolished = 0 THEN l.lawd_cd ELSE s.새코드 END,
       표시 = CASE WHEN l.is_abolished = 0 OR b.말소일자 IS NULL THEN l.full_nm
                   ELSE N'옛 ' + l.full_nm + N' (' + LEFT(b.말소일자, 4) + N'.' + SUBSTRING(b.말소일자, 5, 2) + N'.' + RIGHT(b.말소일자, 2) + N' 폐지)' END,
       출처 = N'사전'
  FROM meta.lawd_code l
  LEFT JOIN gold.v_bdong_code b ON b.법정동코드 = l.lawd_cd
  LEFT JOIN gold.bdong_succ_code s ON s.옛코드 = l.lawd_cd
UNION ALL
SELECT b.법정동코드, b.시도명, b.시군구명, b.읍면동명, b.동리명,
       LTRIM(CONCAT(b.시도명, N' ' + b.시군구명, N' ' + b.읍면동명, N' ' + b.동리명)),
       b.현행, b.말소일자,
       CASE WHEN b.현행 = 1 THEN b.법정동코드 ELSE s.새코드 END,
       CASE WHEN b.현행 = 1 THEN LTRIM(CONCAT(b.시도명, N' ' + b.시군구명, N' ' + b.읍면동명, N' ' + b.동리명))
            ELSE N'옛 ' + LTRIM(CONCAT(b.시도명, N' ' + b.시군구명, N' ' + b.읍면동명, N' ' + b.동리명))
                 + N' (' + LEFT(b.말소일자, 4) + N'.' + SUBSTRING(b.말소일자, 5, 2) + N'.' + RIGHT(b.말소일자, 2) + N' 폐지)' END,
       N'행안부이력'
  FROM gold.v_bdong_code b
  LEFT JOIN gold.bdong_succ_code s ON s.옛코드 = b.법정동코드
 WHERE NOT EXISTS (SELECT 1 FROM meta.lawd_code l WHERE l.lawd_cd = b.법정동코드);
GO
