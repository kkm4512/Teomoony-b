/* 309_ned_ho_link : 연립·다세대 공동주택가격(306, VWorld NED) → 호 잇기 · 화면(동·호 탭) (2026-10-22 사장님 "연립공시가 화면 안 넣은 이유 있어?")
   ★ 잇는 길 = **같은 PNU + 동명·호명**(코드로 받은 필지 안에서, 대장 전유부의 동명·호명과). 이름(단지명)은 안 쓴다.
     맞춤: 공백 빼고, 동명 끝 '동' · 호명 끝 '호' 를 떼고 비교('8동'='8', '101호'='101'). 동명 빈칸은 빈칸끼리.
   ★ **양쪽 다 하나**일 때만 잇는다 — 한 호에 NED 후보가 둘 이상이거나, NED 한 키에 호가 둘 이상이면 잇지 않는다.
   ★ 건축HUB 주택가격(silver.bld_hsprc, 27)이 있는 호는 그대로 그것만 쓴다 — 두 출처를 한 호에 섞지 않는다.
     NED 는 **HUB 값이 하나도 없는 호**에만 들어간다(성북 연립 6,225호 중 HUB 62 · 다세대 30,993 중 1).
   ★ 기준일 = 기준연도+기준월+'01'(NED 는 공시일을 안 준다 — 공시일 칸은 비운다). */
SET NOCOUNT ON;
GO
IF OBJECT_ID('gold.ned_ho_link') IS NULL
CREATE TABLE gold.ned_ho_link (
    호PK         VARCHAR(50)   NOT NULL CONSTRAINT pk_ned_ho_link PRIMARY KEY,
    pnu          CHAR(19)      NOT NULL,
    공동주택코드 VARCHAR(20)   NOT NULL,
    동명         NVARCHAR(100) NOT NULL,
    호명         NVARCHAR(100) NOT NULL,
    맞춤         NVARCHAR(30)  NULL,          -- 동명·호명 · 호명(한쪽 동명 빈칸)
    만든시각     DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);
GO
IF COL_LENGTH('gold.ned_ho_link', '맞춤') IS NULL ALTER TABLE gold.ned_ho_link ADD 맞춤 NVARCHAR(30) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_ned_ho_link_key' AND object_id = OBJECT_ID('gold.ned_ho_link'))
CREATE INDEX ix_ned_ho_link_key ON gold.ned_ho_link (pnu, 공동주택코드, 동명, 호명);
GO
CREATE OR ALTER PROCEDURE gold.usp_build_ned_ho_link AS
BEGIN
  SET NOCOUNT ON;
  IF OBJECT_ID('tempdb..#e309') IS NOT NULL DROP TABLE #e309;
  SELECT 호PK = e.mgm_bldrgst_pk, e.pnu,
         d = REPLACE(ISNULL(e.dong_nm, ''), N' ', ''), h = REPLACE(ISNULL(e.ho_nm, ''), N' ', '')
    INTO #e309
    FROM silver.bld_expos e
   WHERE e.is_current = 1 AND e.pnu IN (SELECT pnu FROM silver.ned_aphus_done)
     AND NOT EXISTS (SELECT 1 FROM silver.bld_hsprc hp WHERE hp.mgm_bldrgst_pk = e.mgm_bldrgst_pk AND hp.is_current = 1 AND hp.hsprc > 0);
  UPDATE #e309 SET d = CASE WHEN d LIKE N'%동' AND LEN(d) > 1 THEN LEFT(d, LEN(d) - 1) ELSE d END,
                   h = CASE WHEN h LIKE N'%호' AND LEN(h) > 1 THEN LEFT(h, LEN(h) - 1) ELSE h END;
  CREATE INDEX ix ON #e309 (pnu, d, h);

  IF OBJECT_ID('tempdb..#n309') IS NOT NULL DROP TABLE #n309;
  SELECT DISTINCT n.pnu, n.공동주택코드, n.동명, n.호명,
         d = REPLACE(n.동명, N' ', ''), h = REPLACE(n.호명, N' ', '')
    INTO #n309
    FROM silver.ned_aphus_price n;
  UPDATE #n309 SET d = CASE WHEN d LIKE N'%동' AND LEN(d) > 1 THEN LEFT(d, LEN(d) - 1) ELSE d END,
                   h = CASE WHEN h LIKE N'%호' AND LEN(h) > 1 THEN LEFT(h, LEN(h) - 1) ELSE h END;
  CREATE INDEX ix ON #n309 (pnu, d, h);

  IF OBJECT_ID('tempdb..#m309') IS NOT NULL DROP TABLE #m309;
  SELECT e.호PK, n.pnu, n.공동주택코드, n.동명, n.호명,
         호후보 = COUNT(*) OVER (PARTITION BY e.호PK),
         키후보 = COUNT(*) OVER (PARTITION BY n.pnu, n.공동주택코드, n.동명, n.호명)
    INTO #m309
    FROM #e309 e JOIN #n309 n ON n.pnu = e.pnu AND n.d = e.d AND n.h = e.h
   WHERE e.h <> '';

  TRUNCATE TABLE gold.ned_ho_link;
  INSERT gold.ned_ho_link (호PK, pnu, 공동주택코드, 동명, 호명, 맞춤)
  SELECT 호PK, pnu, 공동주택코드, 동명, 호명, N'동명·호명' FROM #m309 WHERE 호후보 = 1 AND 키후보 = 1;

  /* 2차 (2026-10-22 표본 30개 중 다수): **한쪽 동명이 빈칸**('' ↔ '1'·'다'·'C', '주건축물제1동' ↔ '').
     그 필지 안에서 **그 호명이 양쪽에 하나씩뿐**일 때만 호명으로 잇는다 — 가동·나동이 같은 101호를 가지면 둘 다 안 잇는다.
     세는 범위는 1차에서 이어진 것까지 **포함한 필지 전체**(남은 것만 세면 하나뿐인 것처럼 보일 수 있다). */
  IF OBJECT_ID('tempdb..#ec309') IS NOT NULL DROP TABLE #ec309;
  SELECT pnu, h, n = COUNT(*) INTO #ec309 FROM #e309 WHERE h <> '' GROUP BY pnu, h;
  IF OBJECT_ID('tempdb..#nc309') IS NOT NULL DROP TABLE #nc309;
  SELECT pnu, h, n = COUNT(*) INTO #nc309 FROM #n309 WHERE h <> '' GROUP BY pnu, h;
  INSERT gold.ned_ho_link (호PK, pnu, 공동주택코드, 동명, 호명, 맞춤)
  SELECT e.호PK, n.pnu, n.공동주택코드, n.동명, n.호명, N'호명(한쪽 동명 빈칸)'
    FROM #e309 e
    JOIN #n309 n ON n.pnu = e.pnu AND n.h = e.h AND (e.d = '' OR n.d = '') AND e.d <> n.d
    JOIN #ec309 ec ON ec.pnu = e.pnu AND ec.h = e.h AND ec.n = 1
    JOIN #nc309 nc ON nc.pnu = n.pnu AND nc.h = n.h AND nc.n = 1
   WHERE e.h <> ''
     AND NOT EXISTS (SELECT 1 FROM gold.ned_ho_link l WHERE l.호PK = e.호PK)
     AND NOT EXISTS (SELECT 1 FROM gold.ned_ho_link l WHERE l.pnu = n.pnu AND l.공동주택코드 = n.공동주택코드 AND l.동명 = n.동명 AND l.호명 = n.호명);

  SELECT 대상호 = (SELECT COUNT(*) FROM #e309),
         이음 = (SELECT COUNT(*) FROM gold.ned_ho_link), 이음2차 = (SELECT COUNT(*) FROM gold.ned_ho_link WHERE 맞춤 <> N'동명·호명'),
         후보여럿 = (SELECT COUNT(DISTINCT 호PK) FROM #m309 WHERE 호후보 > 1 OR 키후보 > 1),
         못찾음 = (SELECT COUNT(*) FROM #e309 e WHERE NOT EXISTS (SELECT 1 FROM gold.ned_ho_link l WHERE l.호PK = e.호PK));
END
GO
/* 한 호의 공시가격 회차 — HUB(27) 가 있으면 HUB 만, 없으면 이어진 NED. 화면(격자·추이·호 모달)이 다 이것을 본다. */
CREATE OR ALTER VIEW gold.v_ho_hsprc AS
SELECT 호PK = e.mgm_bldrgst_pk, e.std_day, e.crtn_day, e.hsprc, 출처 = CAST('HUB' AS VARCHAR(3))
  FROM silver.bld_hsprc e
 WHERE e.is_current = 1 AND e.hsprc > 0
UNION ALL
SELECT l.호PK, std_day = CAST(n.기준연도 + n.기준월 + '01' AS CHAR(8)), crtn_day = CAST(NULL AS CHAR(8)),
       hsprc = CAST(n.공시가격 AS DECIMAL(18, 0)), 출처 = CAST('NED' AS VARCHAR(3))
  FROM gold.ned_ho_link l
  JOIN silver.ned_aphus_price n ON n.pnu = l.pnu AND n.공동주택코드 = l.공동주택코드 AND n.동명 = l.동명 AND n.호명 = l.호명
 WHERE n.공시가격 > 0;
GO
/* 29_hsprc_tie 의 뷰를 그대로 두고 **출처만** 바꾼다(창 함수 파티션 맨 앞 complex_id — 그 이유는 29 주석). */
CREATE OR ALTER VIEW gold.v_complex_ho_price
AS
WITH j AS (
    SELECT h.complex_id, h.호PK, h.동PK, h.동, h.층, h.호, h.라인,
           기준일 = e.std_day, 공시일 = e.crtn_day, 공시가격 = e.hsprc, 출처 = e.출처,
           rn   = ROW_NUMBER() OVER (PARTITION BY h.complex_id, h.호PK
                                     ORDER BY e.std_day DESC, e.crtn_day DESC),
           회차 = COUNT(*)     OVER (PARTITION BY h.complex_id, h.호PK, e.std_day)
    FROM gold.v_complex_ho h
    JOIN gold.v_ho_hsprc e ON e.호PK = h.호PK
),
k AS (
    SELECT * FROM j WHERE rn = 1
),
r AS (
    SELECT k.*,
           단지cd   = CUME_DIST() OVER (PARTITION BY k.complex_id ORDER BY k.공시가격),
           단지최저 = MIN(k.공시가격) OVER (PARTITION BY k.complex_id),
           단지최고 = MAX(k.공시가격) OVER (PARTITION BY k.complex_id),
           단지종류 = DENSE_RANK() OVER (PARTITION BY k.complex_id ORDER BY k.공시가격)
                    + DENSE_RANK() OVER (PARTITION BY k.complex_id ORDER BY k.공시가격 DESC) - 1,
           라인cd   = CUME_DIST() OVER (PARTITION BY k.complex_id, k.동PK, k.라인
                                        ORDER BY k.공시가격),
           라인최저 = MIN(k.공시가격) OVER (PARTITION BY k.complex_id, k.동PK, k.라인),
           라인최고 = MAX(k.공시가격) OVER (PARTITION BY k.complex_id, k.동PK, k.라인),
           라인종류 = DENSE_RANK() OVER (PARTITION BY k.complex_id, k.동PK, k.라인
                                        ORDER BY k.공시가격)
                    + DENSE_RANK() OVER (PARTITION BY k.complex_id, k.동PK, k.라인
                                        ORDER BY k.공시가격 DESC) - 1
    FROM k
)
SELECT complex_id, 호PK, 동PK, 동, 층, 호, 라인,
       기준일, 공시일, 공시가격, 공시회차 = 회차, 출처,
       단지분위 = CASE WHEN 단지최저 < 단지최고
                       THEN CONVERT(INT, CEILING(5.0 * 단지cd)) END,
       라인분위 = CASE WHEN 라인최저 < 라인최고
                       THEN CONVERT(INT, CEILING(5.0 * 라인cd)) END,
       단지값종류 = 단지종류,
       라인값종류 = 라인종류,
       단지최저, 단지최고, 라인최저, 라인최고
FROM r;
GO
