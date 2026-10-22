/* 308_region_master : 법정동·행정동 마스터와 변경 이력 (2026-10-22 사장님 "법정동,행정동 마스터가 필요해 · 변경전으로 검색해도 변경후로")
   원천 = 국가데이터처_법정동 연계정보 (공공데이터포털 15136368, 파일만 — API 없음)
          · 20250602 판: 2013.04~2025.04 분기별 (엑셀 행 한도 1,048,575 에 걸려 **2013.04 분기만 잘림**)
          · 20261001 판: 2025.10~2026.10 분기별
          → 2025.07 분기는 어느 판에도 없다(비어 있음).
   ★ silver.region_link 는 원문 그대로(분기마다 행정동↔법정동 한 쌍 한 줄). 고치지 않는다.
   ★ 변경은 '앞 분기에 있고 뒤 분기에 없는 코드' 로만 찾는다 — 실제 시행일은 두 분기 **사이** 어딘가다(그렇게 적는다).
   ★ 옛 행정동 → 새 행정동 잇기 = **같은 법정동을 나눠 가진 것**(공식 대응표의 겹침). 이름으로 잇지 않는다.
     하나가 여럿으로 나뉘거나 여럿이 합쳐지면 **후보 전부**를 적는다(1:1 로 우기지 않는다). */
SET NOCOUNT ON;
GO
IF OBJECT_ID('silver.region_link') IS NULL
CREATE TABLE silver.region_link (
    개정일자     DATE          NOT NULL,
    행정동코드   CHAR(10)      NOT NULL,
    법정동코드   CHAR(10)      NOT NULL,
    시도명       NVARCHAR(40)  NULL,
    시군구명     NVARCHAR(40)  NULL,
    행정동명     NVARCHAR(40)  NULL,
    법정동명     NVARCHAR(40)  NULL,
    행정구역코드 VARCHAR(10)   NULL,     -- 통계청 행정구역분류(7·8자리 섞임, 원문 그대로)
    연결번호     NVARCHAR(200) NULL,     -- 원문 그대로: '2070, 4353, 4354, 4355' 처럼 여럿일 때가 있다
    원본파일     CHAR(8)       NOT NULL, -- 20250602 · 20261001
    받은시각     DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_region_link PRIMARY KEY CLUSTERED (개정일자, 행정동코드, 법정동코드)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_region_link_b' AND object_id = OBJECT_ID('silver.region_link'))
CREATE INDEX ix_region_link_b ON silver.region_link (법정동코드, 개정일자) INCLUDE (행정동코드);
GO
/* 분기 목록. 완전 = 0 이면 변경 찾기에 쓰지 않는다(2013.04 = 잘린 분기). */
IF OBJECT_ID('silver.region_link_snap') IS NULL
CREATE TABLE silver.region_link_snap (
    개정일자 DATE NOT NULL CONSTRAINT pk_region_link_snap PRIMARY KEY,
    행수     INT  NOT NULL,
    완전     BIT  NOT NULL,
    왜       NVARCHAR(200) NULL
);
GO
/* ---------- 파생표 (다시 만들 수 있다) ---------- */
IF OBJECT_ID('gold.region_hdong') IS NULL
CREATE TABLE gold.region_hdong (
    행정동코드 CHAR(10) NOT NULL CONSTRAINT pk_region_hdong PRIMARY KEY,
    시도명 NVARCHAR(40) NULL, 시군구명 NVARCHAR(40) NULL, 행정동명 NVARCHAR(40) NULL,   -- 마지막으로 본 분기의 이름
    처음본분기 DATE NOT NULL, 마지막본분기 DATE NOT NULL,
    현행 BIT NOT NULL
);
GO
IF OBJECT_ID('gold.region_bdong') IS NULL
CREATE TABLE gold.region_bdong (
    법정동코드 CHAR(10) NOT NULL CONSTRAINT pk_region_bdong PRIMARY KEY,
    시도명 NVARCHAR(40) NULL, 시군구명 NVARCHAR(40) NULL, 법정동명 NVARCHAR(40) NULL,
    처음본분기 DATE NOT NULL, 마지막본분기 DATE NOT NULL,
    현행 BIT NOT NULL
);
GO
/* 행정동 바뀜: 앞 분기(전)에 있던 옛 코드가 뒤 분기(후)에 없고, 뒤 분기에 새 코드가 생겼을 때 — 같은 법정동을 나눠 가진 쌍.
   종류: 생김(옛 짝 없음) · 없어짐(새 짝 없음) · 이어짐(짝 있음). 옛 하나에 새가 여럿 = 나뉨, 새 하나에 옛이 여럿 = 합침. */
IF OBJECT_ID('gold.region_hdong_change') IS NULL
CREATE TABLE gold.region_hdong_change (
    전분기 DATE NOT NULL, 후분기 DATE NOT NULL,
    옛코드 CHAR(10) NULL, 옛이름 NVARCHAR(90) NULL,
    새코드 CHAR(10) NULL, 새이름 NVARCHAR(90) NULL,
    겹친법정동 INT NULL,
    옛짝수 INT NULL, 새짝수 INT NULL      -- 이 옛 코드가 이어진 새 코드 수 / 이 새 코드로 이어진 옛 코드 수
);
GO
IF OBJECT_ID('gold.region_bdong_change') IS NULL
CREATE TABLE gold.region_bdong_change (
    전분기 DATE NOT NULL, 후분기 DATE NOT NULL,
    법정동코드 CHAR(10) NOT NULL, 이름 NVARCHAR(90) NULL,
    종류 NVARCHAR(10) NOT NULL       -- 생김 · 없어짐 (짝 찾기는 전국 법정동 API 로 따로)
);
GO
CREATE OR ALTER PROCEDURE gold.usp_build_region AS
BEGIN
  SET NOCOUNT ON;
  /* 분기 목록 — 2013.04 는 잘린 분기 */
  MERGE silver.region_link_snap AS t
  USING (SELECT 개정일자, n = COUNT(*) FROM silver.region_link GROUP BY 개정일자) s ON t.개정일자 = s.개정일자
  WHEN MATCHED THEN UPDATE SET 행수 = s.n
  WHEN NOT MATCHED THEN INSERT (개정일자, 행수, 완전, 왜)
    VALUES (s.개정일자, s.n, CASE WHEN s.개정일자 = '2013-04-01' THEN 0 ELSE 1 END,
            CASE WHEN s.개정일자 = '2013-04-01' THEN N'20250602 판이 엑셀 행 한도(1,048,575)에서 잘림 — 이 분기 일부만 있음' END);

  DECLARE @최신 DATE = (SELECT MAX(개정일자) FROM silver.region_link_snap WHERE 완전 = 1);

  IF OBJECT_ID('tempdb..#rl308') IS NOT NULL DROP TABLE #rl308;
  SELECT l.* INTO #rl308 FROM silver.region_link l JOIN silver.region_link_snap s ON s.개정일자 = l.개정일자 AND s.완전 = 1;
  CREATE CLUSTERED INDEX cx ON #rl308 (개정일자, 행정동코드, 법정동코드);

  TRUNCATE TABLE gold.region_hdong;
  INSERT gold.region_hdong (행정동코드, 시도명, 시군구명, 행정동명, 처음본분기, 마지막본분기, 현행)
  SELECT a.행정동코드, n.시도명, n.시군구명, n.행정동명, a.처음, a.마지막, CASE WHEN a.마지막 = @최신 THEN 1 ELSE 0 END
    FROM (SELECT 행정동코드, 처음 = MIN(개정일자), 마지막 = MAX(개정일자) FROM #rl308 GROUP BY 행정동코드) a
   CROSS APPLY (SELECT TOP 1 시도명, 시군구명, 행정동명 FROM #rl308 x WHERE x.행정동코드 = a.행정동코드 AND x.개정일자 = a.마지막) n;

  TRUNCATE TABLE gold.region_bdong;
  INSERT gold.region_bdong (법정동코드, 시도명, 시군구명, 법정동명, 처음본분기, 마지막본분기, 현행)
  SELECT a.법정동코드, n.시도명, n.시군구명, n.법정동명, a.처음, a.마지막, CASE WHEN a.마지막 = @최신 THEN 1 ELSE 0 END
    FROM (SELECT 법정동코드, 처음 = MIN(개정일자), 마지막 = MAX(개정일자) FROM #rl308 GROUP BY 법정동코드) a
   CROSS APPLY (SELECT TOP 1 시도명, 시군구명, 법정동명 FROM #rl308 x WHERE x.법정동코드 = a.법정동코드 AND x.개정일자 = a.마지막) n;

  /* 이웃한 분기 쌍 */
  IF OBJECT_ID('tempdb..#pair308') IS NOT NULL DROP TABLE #pair308;
  SELECT 전 = a.개정일자, 후 = b.개정일자 INTO #pair308
    FROM (SELECT 개정일자, n = ROW_NUMBER() OVER (ORDER BY 개정일자) FROM silver.region_link_snap WHERE 완전 = 1) a
    JOIN (SELECT 개정일자, n = ROW_NUMBER() OVER (ORDER BY 개정일자) FROM silver.region_link_snap WHERE 완전 = 1) b ON b.n = a.n + 1;

  IF OBJECT_ID('tempdb..#h308') IS NOT NULL DROP TABLE #h308;
  SELECT DISTINCT 개정일자, 행정동코드 INTO #h308 FROM #rl308;
  CREATE UNIQUE CLUSTERED INDEX cx ON #h308 (개정일자, 행정동코드);

  IF OBJECT_ID('tempdb..#gone308') IS NOT NULL DROP TABLE #gone308;
  SELECT p.전, p.후, h.행정동코드 INTO #gone308 FROM #pair308 p JOIN #h308 h ON h.개정일자 = p.전
   WHERE NOT EXISTS (SELECT 1 FROM #h308 x WHERE x.개정일자 = p.후 AND x.행정동코드 = h.행정동코드);
  IF OBJECT_ID('tempdb..#new308') IS NOT NULL DROP TABLE #new308;
  SELECT p.전, p.후, h.행정동코드 INTO #new308 FROM #pair308 p JOIN #h308 h ON h.개정일자 = p.후
   WHERE NOT EXISTS (SELECT 1 FROM #h308 x WHERE x.개정일자 = p.전 AND x.행정동코드 = h.행정동코드);

  IF OBJECT_ID('tempdb..#m308') IS NOT NULL DROP TABLE #m308;
  SELECT g.전, g.후, 옛코드 = g.행정동코드, 새코드 = n.행정동코드, 겹친법정동 = COUNT(DISTINCT a.법정동코드)
    INTO #m308
    FROM #gone308 g JOIN #new308 n ON n.전 = g.전 AND n.후 = g.후
    JOIN #rl308 a ON a.개정일자 = g.전 AND a.행정동코드 = g.행정동코드
    JOIN #rl308 b ON b.개정일자 = g.후 AND b.행정동코드 = n.행정동코드 AND b.법정동코드 = a.법정동코드
   GROUP BY g.전, g.후, g.행정동코드, n.행정동코드;

  TRUNCATE TABLE gold.region_hdong_change;
  INSERT gold.region_hdong_change (전분기, 후분기, 옛코드, 옛이름, 새코드, 새이름, 겹친법정동, 옛짝수, 새짝수)
  SELECT m.전, m.후, m.옛코드, NULL, m.새코드, NULL, m.겹친법정동,
         COUNT(*) OVER (PARTITION BY m.전, m.옛코드), COUNT(*) OVER (PARTITION BY m.전, m.새코드)
    FROM #m308 m
  UNION ALL
  SELECT g.전, g.후, g.행정동코드, NULL, NULL, NULL, NULL, 0, NULL FROM #gone308 g
   WHERE NOT EXISTS (SELECT 1 FROM #m308 m WHERE m.전 = g.전 AND m.옛코드 = g.행정동코드)
  UNION ALL
  SELECT n.전, n.후, NULL, NULL, n.행정동코드, NULL, NULL, NULL, 0 FROM #new308 n
   WHERE NOT EXISTS (SELECT 1 FROM #m308 m WHERE m.전 = n.전 AND m.새코드 = n.행정동코드);

  /* 이름: 옛 이름은 '전' 분기, 새 이름은 '후' 분기 원문 */
  UPDATE c SET 옛이름 = o.nm FROM gold.region_hdong_change c
   CROSS APPLY (SELECT TOP 1 nm = CONCAT(시도명, N' ', 시군구명, N' ', 행정동명) FROM #rl308 x WHERE x.개정일자 = c.전분기 AND x.행정동코드 = c.옛코드) o
   WHERE c.옛코드 IS NOT NULL;
  UPDATE c SET 새이름 = o.nm FROM gold.region_hdong_change c
   CROSS APPLY (SELECT TOP 1 nm = CONCAT(시도명, N' ', 시군구명, N' ', 행정동명) FROM #rl308 x WHERE x.개정일자 = c.후분기 AND x.행정동코드 = c.새코드) o
   WHERE c.새코드 IS NOT NULL;

  /* 법정동 생김·없어짐 */
  IF OBJECT_ID('tempdb..#b308') IS NOT NULL DROP TABLE #b308;
  SELECT DISTINCT 개정일자, 법정동코드 INTO #b308 FROM #rl308;
  CREATE UNIQUE CLUSTERED INDEX cx ON #b308 (개정일자, 법정동코드);
  TRUNCATE TABLE gold.region_bdong_change;
  INSERT gold.region_bdong_change (전분기, 후분기, 법정동코드, 이름, 종류)
  SELECT p.전, p.후, b.법정동코드, NULL, N'없어짐' FROM #pair308 p JOIN #b308 b ON b.개정일자 = p.전
   WHERE NOT EXISTS (SELECT 1 FROM #b308 x WHERE x.개정일자 = p.후 AND x.법정동코드 = b.법정동코드)
  UNION ALL
  SELECT p.전, p.후, b.법정동코드, NULL, N'생김' FROM #pair308 p JOIN #b308 b ON b.개정일자 = p.후
   WHERE NOT EXISTS (SELECT 1 FROM #b308 x WHERE x.개정일자 = p.전 AND x.법정동코드 = b.법정동코드);
  UPDATE c SET 이름 = o.nm FROM gold.region_bdong_change c
   CROSS APPLY (SELECT TOP 1 nm = CONCAT(시도명, N' ', 시군구명, N' ', 법정동명) FROM #rl308 x
                 WHERE x.개정일자 = CASE WHEN c.종류 = N'없어짐' THEN c.전분기 ELSE c.후분기 END AND x.법정동코드 = c.법정동코드) o;

  SELECT 최신분기 = @최신,
         분기 = (SELECT COUNT(*) FROM silver.region_link_snap WHERE 완전 = 1),
         행정동 = (SELECT COUNT(*) FROM gold.region_hdong), 행정동현행 = (SELECT COUNT(*) FROM gold.region_hdong WHERE 현행 = 1),
         법정동 = (SELECT COUNT(*) FROM gold.region_bdong), 법정동현행 = (SELECT COUNT(*) FROM gold.region_bdong WHERE 현행 = 1),
         행정동바뀜 = (SELECT COUNT(*) FROM gold.region_hdong_change), 법정동바뀜 = (SELECT COUNT(*) FROM gold.region_bdong_change);
END
GO
/* 2026-10-22: 연결번호가 '2070, 4353, 4354, 4355' 처럼 여럿일 때가 있어 INT 로는 못 받는다 → 글자로 */
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('silver.region_link') AND name = N'연결번호' AND system_type_id = 56)
ALTER TABLE silver.region_link ALTER COLUMN 연결번호 NVARCHAR(200) NULL;
GO
