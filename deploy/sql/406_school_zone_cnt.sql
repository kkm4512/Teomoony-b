/* 406 (2026-11-01 사장님 "괜찮은거니" — 학교 상세가 60초 넘어 끊김)
   학교 상세의 '구역 안 단지 · 세대' 셈을 화면이 열릴 때마다 하던 것을 **미리 센 표**로 옮긴다(같은 조건 · 같은 셈 — 값은 그대로).
   ★ 단지가 늘어 학군(넓은 고등학교 군)마다 단지 수십만 개를 경계 안인지 하나씩 재다 한 번에 2억 5천만 페이지를 읽었다.
   ★ 조건(옛 질의 그대로): is_active = 1 · merged_into 없음 · 중심 좌표 있음 · 세대 > 0 · 구역 경계가 중심점을 품음(STContains — 경계선 위는 안 셈).
   ★ 열쇠 = (출처, 번호, 종류): 학구(초등, silver.school_zone)는 'Z' · 학교군(중 · 고, silver.school_group)은 'G' + kind.
     상세는 옛 COALESCE 순서대로 학구 경계가 있으면 'Z', 없으면 'G' 를 읽는다. 표에 없는 구역(새로 들어온 경계)은 상세가 그 자리에서 센다. */
CREATE OR ALTER PROCEDURE gold.usp_build_school_zone_cnt AS
BEGIN
  SET NOCOUNT ON;
  IF OBJECT_ID('gold.school_zone_cnt') IS NULL
  BEGIN
    SELECT TOP 0 출처 = CAST('Z' AS CHAR(1)), z.hakgudo_id, 종류 = CAST('' AS VARCHAR(4)), n = CAST(0 AS INT), hh = CAST(0 AS BIGINT), 셈때 = CAST(NULL AS DATETIME2(0))
      INTO gold.school_zone_cnt FROM silver.school_zone z;
    ALTER TABLE gold.school_zone_cnt ALTER COLUMN hakgudo_id VARCHAR(60) NOT NULL;
    ALTER TABLE gold.school_zone_cnt ALTER COLUMN 출처 CHAR(1) NOT NULL;
    ALTER TABLE gold.school_zone_cnt ALTER COLUMN 종류 VARCHAR(4) NOT NULL;
    ALTER TABLE gold.school_zone_cnt ADD CONSTRAINT pk_school_zone_cnt PRIMARY KEY (출처, hakgudo_id, 종류);
  END
  IF OBJECT_ID('tempdb..#c') IS NOT NULL DROP TABLE #c;
  SELECT id = IDENTITY(INT, 1, 1), hh = CAST(hhld_cnt_sum AS BIGINT), pt = geometry::Point(centroid_lng, centroid_lat, 4326)
    INTO #c
    FROM gold.complex WHERE is_active = 1 AND merged_into IS NULL AND centroid_lat IS NOT NULL AND centroid_lng IS NOT NULL AND hhld_cnt_sum > 0;
  ALTER TABLE #c ADD CONSTRAINT pk_c PRIMARY KEY (id);
  CREATE SPATIAL INDEX sx_c ON #c (pt) WITH (BOUNDING_BOX = (124, 33, 132, 39));
  IF OBJECT_ID('tempdb..#n') IS NOT NULL DROP TABLE #n;
  CREATE TABLE #n (출처 CHAR(1) NOT NULL, hakgudo_id VARCHAR(60) NOT NULL, 종류 VARCHAR(4) NOT NULL, n INT NOT NULL, hh BIGINT NULL);
  INSERT INTO #n
  SELECT 'Z', z.hakgudo_id, '', ISNULL(x.n, 0), x.hh
    FROM silver.school_zone z
    OUTER APPLY (SELECT n = COUNT(*), hh = SUM(c.hh) FROM #c c WITH (INDEX(sx_c)) WHERE z.geom.STContains(c.pt) = 1) x
   WHERE z.geom IS NOT NULL;
  INSERT INTO #n
  SELECT 'G', g.hakgudo_id, ISNULL(g.kind, ''), ISNULL(x.n, 0), x.hh
    FROM silver.school_group g
    OUTER APPLY (SELECT n = COUNT(*), hh = SUM(c.hh) FROM #c c WITH (INDEX(sx_c)) WHERE g.geom.STContains(c.pt) = 1) x
   WHERE g.geom IS NOT NULL;
  BEGIN TRAN;
    DELETE FROM gold.school_zone_cnt;
    INSERT INTO gold.school_zone_cnt (출처, hakgudo_id, 종류, n, hh, 셈때)
    SELECT 출처, hakgudo_id, 종류, MAX(n), MAX(hh), SYSDATETIME() FROM #n GROUP BY 출처, hakgudo_id, 종류;
  COMMIT;
  SELECT 출처, 구역 = COUNT(*), 단지합 = SUM(n), 세대합 = SUM(hh) FROM gold.school_zone_cnt GROUP BY 출처;
END
GO
MERGE ops.collect_schedule AS d
USING (VALUES (N'학교 구역 안 단지 셈', N'파생(학교)', 'cl-school-zone-cnt-par', 'daily 07:45', N'파생',
               N'학구 · 학교군 경계 안 단지 · 세대 미리 셈(406) — 학교 상세가 그 자리에서 세다 60초 넘던 것', 'once', 1))
      AS s (이름, 자료, 작업, 주기, 출처주기, 근거, 못돎이면, 켜짐)
ON d.작업 = s.작업
WHEN MATCHED THEN UPDATE SET 이름 = s.이름, 자료 = s.자료, 주기 = s.주기, 출처주기 = s.출처주기, 근거 = s.근거, 못돎이면 = s.못돎이면, 켜짐 = s.켜짐
WHEN NOT MATCHED THEN INSERT (이름, 자료, 작업, 주기, 출처주기, 근거, 못돎이면, 켜짐) VALUES (s.이름, s.자료, s.작업, s.주기, s.출처주기, s.근거, s.못돎이면, s.켜짐);
GO
