/* 2026-10-23 학교 위치(교육부 학교ID 'B…', 전국초중등학교위치표준데이터) ↔ 학교알리미(정보공시 학교코드 'S…') 잇기.
   두 체계를 잇는 공식 대응표가 없다 → **이름은 안 보고** 원문 값이 같은 것만:
   학교급 같음 · 설립일 같음 · 우리 학교 점이 학교알리미 법정동(ADRCD_CD) 경계 안 · 양쪽 다 후보 하나
   ★ 위치표준데이터의 '설립일자' 는 학교알리미의 설립일(FOND_YMD) 또는 **개교기념일(FOAS_MEMRD)** 과 같다(996 실측: 못 이은 747 중 734 가 개교일과 같음) — 둘 중 하나가 같으면 같다고 본다.
   ★ 시군구까지 넓히는 길은 뺐다 — 13건 중 1건(중산고 ↔ 대진디자인고, 같은 구 · 같은 설립일)이 다른 학교였다.
   못 이은 학교는 화면에서 학생·교원 칸이 비고 까닭을 적는다. 이름이 같은지는 **검산으로만** 센다. */
IF OBJECT_ID('gold.school_link') IS NULL
CREATE TABLE gold.school_link (
    school_id    VARCHAR(20)   NOT NULL PRIMARY KEY,   -- silver.school.school_id
    schul_code   VARCHAR(12)   NOT NULL,               -- silver.schoolinfo.schul_code
    근거          NVARCHAR(80)  NOT NULL
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ux_school_link_s')
    CREATE UNIQUE INDEX ux_school_link_s ON gold.school_link (schul_code);
GO
CREATE OR ALTER PROCEDURE gold.usp_refresh_school_link
AS
BEGIN
    SET NOCOUNT ON;
    IF OBJECT_ID('tempdb..#a') IS NOT NULL DROP TABLE #a;
    SELECT s.school_id, s.school_nm, s.lat, s.lon,
           knd = CASE s.school_se WHEN N'초등학교' THEN '02' WHEN N'중학교' THEN '03' WHEN N'고등학교' THEN '04' END,
           fond = REPLACE(s.fond_date, '-', '')
      INTO #a FROM silver.school s
     WHERE s.is_current = 1 AND s.lat IS NOT NULL AND s.fond_date IS NOT NULL
       AND s.school_se IN (N'초등학교', N'중학교', N'고등학교');
    IF OBJECT_ID('tempdb..#b') IS NOT NULL DROP TABLE #b;
    SELECT i.schul_code, i.schul_nm, i.knd_code, i.fond_ymd, 개교 = CAST(JSON_VALUE(i.raw_json, '$.FOAS_MEMRD') AS CHAR(8)), i.adrcd_cd
      INTO #b FROM silver.schoolinfo i
     WHERE i.knd_code IN ('02', '03', '04') AND i.fond_ymd IS NOT NULL AND i.adrcd_cd IS NOT NULL;

    /* ① 법정동 경계 */
    IF OBJECT_ID('tempdb..#c1') IS NOT NULL DROP TABLE #c1;
    SELECT a.school_id, b.schul_code
      INTO #c1
      FROM #b b
      JOIN silver.lawd_boundary lb ON lb.lawd_cd = b.adrcd_cd AND lb.is_current = 1
      JOIN #a a ON a.knd = b.knd_code AND (a.fond = b.fond_ymd OR a.fond = b.개교)
               AND lb.geom.STIntersects(geometry::Point(a.lon, a.lat, lb.geom.STSrid)) = 1;
    BEGIN TRAN;
      DELETE FROM gold.school_link;
      INSERT INTO gold.school_link (school_id, schul_code, 근거)
      SELECT c.school_id, MIN(c.schul_code), N'학교급 · 설립일(또는 개교일) 같음 · 학교알리미 법정동 경계 안 · 양쪽 후보 1'
        FROM #c1 c
       WHERE c.school_id IN (SELECT school_id FROM #c1 GROUP BY school_id HAVING COUNT(DISTINCT schul_code) = 1)
         AND c.schul_code IN (SELECT schul_code FROM #c1 GROUP BY schul_code HAVING COUNT(DISTINCT school_id) = 1)
       GROUP BY c.school_id;
    COMMIT;
END
GO
EXEC gold.usp_refresh_school_link;
GO
/* 검산 — 서울 학교(위치표준) 중 이은 수 · 길마다 이름 같은 수/다른 수 · 다른 보기 */
IF OBJECT_ID('tempdb..#v') IS NOT NULL DROP TABLE #v;
SELECT l.school_id, l.schul_code, l.근거, s.school_nm, i.schul_nm,
       같음 = CASE WHEN REPLACE(s.school_nm, ' ', '') = REPLACE(i.schul_nm, ' ', '') THEN 1 ELSE 0 END
  INTO #v
  FROM gold.school_link l JOIN silver.school s ON s.school_id = l.school_id AND s.is_current = 1
  JOIN silver.schoolinfo i ON i.schul_code = l.schul_code;
SELECT j = (SELECT
  서울학교 = (SELECT COUNT(*) FROM silver.school WHERE is_current = 1 AND (lnmadr LIKE N'서울%' OR rdnmadr LIKE N'서울%') AND school_se IN (N'초등학교', N'중학교', N'고등학교')),
  알리미 = (SELECT COUNT(*) FROM silver.schoolinfo WHERE knd_code IN ('02','03','04')),
  이음 = (SELECT COUNT(*) FROM #v),
  길 = (SELECT 근거, n = COUNT(*), 이름같음 = SUM(같음) FROM #v GROUP BY 근거 FOR JSON PATH),
  이름다름 = (SELECT TOP 30 school_nm, schul_nm, 근거 FROM #v WHERE 같음 = 0 FOR JSON PATH)
  FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
