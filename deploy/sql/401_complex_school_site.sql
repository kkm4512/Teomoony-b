/* 401 학교 · 유치원이 든 단지 (2026-11-01 사장님 "장위초등학교가 검색에서 갈라져 나오고 그걸 눌러야 학교 정보가 떠서 불편" → "ㄱㄱ")
   ★ 이름으로 잇지 않는다 — **위치(코드 · 도형)** 로만: 학교(유치원) 좌표가 든 지금 지적 필지(silver.cadastral_parcel, 도형) →
     그 필지 PNU 를 가진 단지(gold.complex_pnu). 좌표가 필지 하나에만 들고 · 그 필지의 단지가 하나일 때만 잇는다(둘 이상이면 안 잇는다).
   ★ 쓰는 곳: 자동완성(학교 · 유치원 줄을 그 단지 줄과 하나로) · 단지 상세 단지정보 탭 맨 위 학교 칸.
   ★ 학교 좌표가 운동장 · 옆 필지에 찍힌 곳은 안 이어진다(그때는 예전처럼 학교 줄이 따로 나온다). */
SET NOCOUNT ON;
GO
IF OBJECT_ID('gold.complex_school_site') IS NULL
CREATE TABLE gold.complex_school_site (
    종류        NVARCHAR(4)   NOT NULL,     -- 학교 · 유치원
    키          VARCHAR(50)   NOT NULL,     -- silver.school.school_id · silver.kindergarten.kinder_cd
    complex_id  INT           NOT NULL,
    pnu         CHAR(19)      NOT NULL,     -- 좌표가 든 지금 필지
    기준일      DATE          NOT NULL,
    CONSTRAINT pk_complex_school_site PRIMARY KEY (종류, 키)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_complex_school_site_cid')
  CREATE INDEX ix_complex_school_site_cid ON gold.complex_school_site (complex_id);
GO
CREATE OR ALTER PROCEDURE gold.usp_build_complex_school_site AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    DECLARE @오늘 DATE = CAST(DATEADD(HOUR, 9, SYSUTCDATETIME()) AS DATE);
    SELECT 종류 = CAST(N'학교' AS NVARCHAR(4)), 키 = CAST(s.school_id AS VARCHAR(50)), lat = CAST(s.lat AS FLOAT), lng = CAST(s.lon AS FLOAT)
      INTO #pt FROM silver.school s WHERE s.is_current = 1 AND s.lat IS NOT NULL AND s.lon IS NOT NULL;
    INSERT #pt SELECT N'유치원', CAST(k.kinder_cd AS VARCHAR(50)), CAST(k.lat AS FLOAT), CAST(k.lng AS FLOAT)
      FROM silver.kindergarten k WHERE k.lat IS NOT NULL AND k.lng IS NOT NULL AND k.kinder_cd IS NOT NULL;
    /* 좌표가 든 필지 */
    SELECT t.종류, t.키, p.pnu, n필지 = COUNT(*) OVER (PARTITION BY t.종류, t.키)
      INTO #f
      FROM #pt t
      JOIN silver.cadastral_parcel p ON p.is_current = 1 AND p.geom IS NOT NULL
       AND p.geom.STIntersects(geometry::Point(t.lng, t.lat, 4326)) = 1;
    /* 그 필지의 단지(묶인 조각 · 쉬는 단지 빼고) */
    SELECT DISTINCT f.종류, f.키, f.pnu, cp.complex_id
      INTO #c
      FROM #f f
      JOIN gold.complex_pnu cp ON cp.pnu = f.pnu
      JOIN gold.complex c ON c.complex_id = cp.complex_id AND c.merged_into IS NULL AND c.is_active = 1
     WHERE f.n필지 = 1;
    BEGIN TRAN;
    DELETE FROM gold.complex_school_site;
    INSERT gold.complex_school_site (종류, 키, complex_id, pnu, 기준일)
    SELECT 종류, 키, MIN(complex_id), MIN(pnu), @오늘 FROM #c GROUP BY 종류, 키 HAVING COUNT(DISTINCT complex_id) = 1;
    COMMIT;
    SELECT 종류, 이음 = COUNT(*), 단지 = COUNT(DISTINCT complex_id),
           전체 = (SELECT COUNT(*) FROM #pt p WHERE p.종류 = g.종류)
      FROM gold.complex_school_site g GROUP BY 종류;
END
GO
EXEC gold.usp_build_complex_school_site;
GO
/* 매일 — 학교 · 유치원 · 단지가 바뀌면 다시(몇 초) · 그다음 자동완성 학교 · 유치원 층을 다시 담는다 */
MERGE ops.collect_schedule AS d
USING (VALUES (N'학교 · 유치원이 든 단지', N'파생(위치)', 'cl-school-site-par', 'daily 07:25', N'파생',
               N'학교 · 유치원 좌표가 든 지적 필지의 단지(401)', 'once', 1))
      AS s (이름, 자료, 작업, 주기, 출처주기, 근거, 못돎이면, 켜짐)
ON d.작업 = s.작업
WHEN MATCHED THEN UPDATE SET 이름 = s.이름, 자료 = s.자료, 주기 = s.주기, 출처주기 = s.출처주기, 근거 = s.근거, 못돎이면 = s.못돎이면, 켜짐 = s.켜짐
WHEN NOT MATCHED THEN INSERT (이름, 자료, 작업, 주기, 출처주기, 근거, 못돎이면, 켜짐) VALUES (s.이름, s.자료, s.작업, s.주기, s.출처주기, s.근거, s.못돎이면, s.켜짐);
GO
