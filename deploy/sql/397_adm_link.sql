/* 397_adm_link : 행정동 경계(통계청 SGIS) ↔ 행안부 행정동 코드 — 공식 연결 (2026-10-31)
   ★ 전에는 경계 안 상가들의 행정동 코드 다수결(silver.adm_boundary.adm_cd_mois · 연결근거 '상가 위치 다수결')로 이었다 — 추정이다.
     이제 **국가데이터처 법정동 연계정보(silver.region_link)의 '행정구역코드'(통계청 행정구역분류)** 로 잇는다. 공식 대응표다.
   ★ 경계 연도마다 가장 잘 맞는 분기를 고른다(그 연도 경계 코드가 가장 많이 나오는 분기, 같으면 늦은 분기).
     실측(2026-10-31): 2025년 경계 3,559개 — 2025.04 분기에서 3,555개 이어짐. 2026.07 이후 분기는 전남광주 통합으로 코드가 바뀌어 3,078개.
   ★ 이은 행안부 코드의 지금 상태는 행안부 이력(silver.mois_hdong_code, 395)에서 — 말소면 '옛 ○○동 (폐지일)'.
     옛 → 새 행정동은 이 표에서 정하지 않는다(행정동 바뀜 안내는 308 region_hdong_change 그대로).
   ★ 상가 다수결 칸(adm_cd_mois · mois_nm)은 지우지 않는다 — 원래 값은 기록이다. 화면은 이 표를 먼저 쓴다. */
SET NOCOUNT ON;
GO
CREATE OR ALTER VIEW gold.v_hdong_code AS
SELECT h.행정동코드, h.시도명, h.시군구명, h.읍면동명, h.생성일자, h.말소일자,
       현행 = CAST(CASE WHEN h.말소일자 IS NULL THEN 1 ELSE 0 END AS BIT), h.판
  FROM silver.mois_hdong_code h
 WHERE h.판 = (SELECT MAX(판) FROM silver.mois_hdong_code);
GO
IF OBJECT_ID('gold.adm_link') IS NULL
CREATE TABLE gold.adm_link (
    adm_cd_sgis  VARCHAR(10)   NOT NULL,
    year         INT           NOT NULL,
    행정동코드   CHAR(10)      NULL,          -- NULL = 연계정보에 없음(이름은 경계 원문만)
    근거분기     DATE          NULL,
    갈래         INT           NOT NULL,      -- 그 분기에서 이 경계 코드가 가리킨 행안부 행정동 수(1 이 정상)
    행정동명     NVARCHAR(40)  NULL,          -- 행안부 원문(읍면동명)
    현행         BIT           NULL,
    말소일자     CHAR(8)       NULL,
    표시         NVARCHAR(120) NULL,          -- 화면에 그대로: 현행이면 이름, 말소면 '옛 이름 (YYYY.MM.DD 폐지)'
    만든때       DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_adm_link PRIMARY KEY (adm_cd_sgis, year)
);
GO
CREATE OR ALTER PROCEDURE gold.usp_build_adm_link AS
BEGIN
    SET NOCOUNT ON;
    SELECT DISTINCT 개정일자, 행정구역코드, 행정동코드 INTO #L FROM silver.region_link WHERE 행정구역코드 IS NOT NULL;
    CREATE CLUSTERED INDEX c ON #L (행정구역코드, 개정일자);

    /* 연도마다 가장 잘 맞는 분기 */
    WITH m AS (SELECT a.year, l.개정일자, n = COUNT(DISTINCT a.adm_cd_sgis)
                 FROM silver.adm_boundary a JOIN #L l ON l.행정구역코드 = a.adm_cd_sgis GROUP BY a.year, l.개정일자),
         r AS (SELECT *, rn = ROW_NUMBER() OVER (PARTITION BY year ORDER BY n DESC, 개정일자 DESC) FROM m)
    SELECT year, 개정일자 INTO #분기 FROM r WHERE rn = 1;

    SELECT a.adm_cd_sgis, a.year, 분기 = q.개정일자,
           갈래 = (SELECT COUNT(DISTINCT l.행정동코드) FROM #L l WHERE l.행정구역코드 = a.adm_cd_sgis AND l.개정일자 = q.개정일자),
           코드 = (SELECT MIN(l.행정동코드) FROM #L l WHERE l.행정구역코드 = a.adm_cd_sgis AND l.개정일자 = q.개정일자)
      INTO #a
      FROM silver.adm_boundary a LEFT JOIN #분기 q ON q.year = a.year;

    BEGIN TRAN;
    DELETE FROM gold.adm_link;
    INSERT gold.adm_link (adm_cd_sgis, year, 행정동코드, 근거분기, 갈래, 행정동명, 현행, 말소일자, 표시)
    SELECT a.adm_cd_sgis, a.year,
           CASE WHEN a.갈래 = 1 THEN a.코드 END, CASE WHEN a.갈래 >= 1 THEN a.분기 END, a.갈래,
           h.읍면동명, h.현행, h.말소일자,
           CASE WHEN h.행정동코드 IS NULL THEN NULL
                WHEN h.현행 = 1 THEN h.읍면동명
                ELSE N'옛 ' + h.읍면동명 + N' (' + LEFT(h.말소일자, 4) + N'.' + SUBSTRING(h.말소일자, 5, 2) + N'.' + RIGHT(h.말소일자, 2) + N' 폐지)' END
      FROM #a a LEFT JOIN gold.v_hdong_code h ON h.행정동코드 = CASE WHEN a.갈래 = 1 THEN a.코드 END;
    COMMIT;

    SELECT year, 경계 = COUNT(*), 이음 = SUM(CASE WHEN 행정동코드 IS NOT NULL THEN 1 ELSE 0 END),
           현행 = SUM(CASE WHEN 현행 = 1 THEN 1 ELSE 0 END), 말소 = SUM(CASE WHEN 현행 = 0 THEN 1 ELSE 0 END),
           갈래여럿 = SUM(CASE WHEN 갈래 > 1 THEN 1 ELSE 0 END), 분기 = MAX(근거분기)
      FROM gold.adm_link GROUP BY year;
END
GO
