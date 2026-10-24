/* 347 변경 로그 (2026-10-24 17:13 사장님 "과거 이력 전부 · 달라진 칼럼을 액션로그식으로 — ㄱㄱ")
   ★ 2단 구조: ① silver 는 버전 행(원천 시점마다 한 줄 · 같은 시점이 다시 오면 SCD2) — 원본 그대로
               ② gold.change_log 는 ① 에서 **뽑아낸** 칼럼별 변화(파생 — 언제든 다시 만든다). 로그만 남기고 행을 버리지 않는다.
   ★ 시점 = **원천 기준**(토지특성은 기준연도) — 우리가 받은 시각이 아니다. 옛날 것부터 받아도 순서가 맞는다.
   ★ 종류: '바뀜' = 원천 시점 사이에 값이 달라짐(2019 → 2020 지목 전 → 대) · '정정' = 같은 시점 값이 나중에 다르게 다시 옴(SCD2 이전 버전)
           · '처음' 은 적지 않는다(첫 값은 바뀐 것이 아니다 — 화면은 첫 시점을 따로 안다).
   ★ 해마다 바뀌는 게 정상인 값(공시지가 · 관리비 금액)은 **시계열**이지 변경이 아니다 — 로그에 넣지 않는다(추이 그래프의 몫).
   첫 자료: 토지특성(silver.land_char) — 대장구분 · 지목 · 면적 · 용도지역(1·2 를 한 묶음) · 이용상황 · 지형높이 · 지형형상 · 도로접면. */
IF OBJECT_ID('gold.change_log') IS NULL
CREATE TABLE gold.change_log (
    log_id   BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT pk_change_log PRIMARY KEY,
    자료     NVARCHAR(30)  NOT NULL,
    키       VARCHAR(60)   NOT NULL,          -- 자료의 자연키(토지특성 = pnu)
    칼럼     NVARCHAR(40)  NOT NULL,          -- 사람이 읽는 이름
    전값     NVARCHAR(200) NULL,
    새값     NVARCHAR(200) NULL,
    전시점   VARCHAR(10)   NULL,              -- 바로 앞 원천 시점(연도 · 연월 · 일자)
    시점     VARCHAR(10)   NOT NULL,          -- 이 값이 처음 나온 원천 시점
    종류     NVARCHAR(10)  NOT NULL,          -- 바뀜 · 정정
    만든때   DATETIME2(0)  NOT NULL CONSTRAINT df_change_log_t DEFAULT SYSDATETIME()
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('gold.change_log') AND name = 'ix_change_log_key')
    CREATE INDEX ix_change_log_key ON gold.change_log (자료, 키, 시점) INCLUDE (칼럼, 전값, 새값, 종류);
GO
CREATE OR ALTER PROCEDURE gold.usp_change_log_land_char @prefix VARCHAR(10) = NULL
AS
BEGIN
    /* @prefix = PNU 앞자리(시군구 5 · 법정동 10)로 좁혀 다시 만들기. NULL 이면 전부. 시군구 단위로 나눠 돈다(한 번에 1,000만 줄을 들지 않게). */
    SET NOCOUNT ON;
    DECLARE @t0 DATETIME2 = SYSDATETIME(), @n BIGINT = 0, @sgg CHAR(5);
    DECLARE @g TABLE (sgg CHAR(5));
    INSERT @g SELECT DISTINCT LEFT(pnu, 5) FROM silver.land_char WHERE is_current = 1 AND (@prefix IS NULL OR pnu LIKE @prefix + '%');
    WHILE EXISTS (SELECT 1 FROM @g)
    BEGIN
        SELECT TOP 1 @sgg = sgg FROM @g ORDER BY sgg;
        DELETE FROM @g WHERE sgg = @sgg;
        BEGIN TRAN;
        DELETE FROM gold.change_log WHERE 자료 = N'토지특성' AND 키 LIKE @sgg + '%' AND (@prefix IS NULL OR 키 LIKE @prefix + '%');
        /* ① 바뀜 — 같은 필지의 연도 순 앞뒤(지금 버전끼리) */
        ;WITH v AS (
            SELECT pnu, base_year,
                   a1 = CAST(regstr_se_code AS NVARCHAR(200)), a2 = CAST(lndcgr_nm AS NVARCHAR(200)), a3 = CAST(CAST(lndpcl_ar AS DECIMAL(19,2)) AS NVARCHAR(200)),
                   /* 용도지역1·2 는 **집합**으로 본다 — 둘의 순서만 바뀐 해(리센츠 2025: 1·2 가 맞바뀜)를 변경으로 적지 않는다. '지정되지않음' 은 빈칸 */
                   a4 = CAST(CASE WHEN NULLIF(NULLIF(prpos_area1_nm, N'지정되지않음'), N'') IS NULL THEN ISNULL(NULLIF(NULLIF(prpos_area2_nm, N'지정되지않음'), N''), N'')
                               WHEN NULLIF(NULLIF(prpos_area2_nm, N'지정되지않음'), N'') IS NULL OR prpos_area2_nm = prpos_area1_nm THEN prpos_area1_nm
                               WHEN prpos_area1_nm < prpos_area2_nm THEN prpos_area1_nm + N' · ' + prpos_area2_nm
                               ELSE prpos_area2_nm + N' · ' + prpos_area1_nm END AS NVARCHAR(200)), a5 = CAST(NULL AS NVARCHAR(200)), a6 = CAST(lad_use_sittn_nm AS NVARCHAR(200)),
                   a7 = CAST(tpgrph_hg_code_nm AS NVARCHAR(200)), a8 = CAST(tpgrph_frm_code_nm AS NVARCHAR(200)), a9 = CAST(road_side_code_nm AS NVARCHAR(200)),
                   py = LAG(base_year) OVER (PARTITION BY pnu ORDER BY base_year),
                   p1 = LAG(CAST(regstr_se_code AS NVARCHAR(200))) OVER (PARTITION BY pnu ORDER BY base_year),
                   p2 = LAG(CAST(lndcgr_nm AS NVARCHAR(200))) OVER (PARTITION BY pnu ORDER BY base_year),
                   p3 = LAG(CAST(CAST(lndpcl_ar AS DECIMAL(19,2)) AS NVARCHAR(200))) OVER (PARTITION BY pnu ORDER BY base_year),
                   p4 = LAG(CAST(CASE WHEN NULLIF(NULLIF(prpos_area1_nm, N'지정되지않음'), N'') IS NULL THEN ISNULL(NULLIF(NULLIF(prpos_area2_nm, N'지정되지않음'), N''), N'')
                               WHEN NULLIF(NULLIF(prpos_area2_nm, N'지정되지않음'), N'') IS NULL OR prpos_area2_nm = prpos_area1_nm THEN prpos_area1_nm
                               WHEN prpos_area1_nm < prpos_area2_nm THEN prpos_area1_nm + N' · ' + prpos_area2_nm
                               ELSE prpos_area2_nm + N' · ' + prpos_area1_nm END AS NVARCHAR(200))) OVER (PARTITION BY pnu ORDER BY base_year),
                   p5 = CAST(NULL AS NVARCHAR(200)),
                   p6 = LAG(CAST(lad_use_sittn_nm AS NVARCHAR(200))) OVER (PARTITION BY pnu ORDER BY base_year),
                   p7 = LAG(CAST(tpgrph_hg_code_nm AS NVARCHAR(200))) OVER (PARTITION BY pnu ORDER BY base_year),
                   p8 = LAG(CAST(tpgrph_frm_code_nm AS NVARCHAR(200))) OVER (PARTITION BY pnu ORDER BY base_year),
                   p9 = LAG(CAST(road_side_code_nm AS NVARCHAR(200))) OVER (PARTITION BY pnu ORDER BY base_year)
              FROM silver.land_char WHERE is_current = 1 AND pnu LIKE @sgg + '%' AND (@prefix IS NULL OR pnu LIKE @prefix + '%') AND base_year IS NOT NULL)
        INSERT gold.change_log (자료, 키, 칼럼, 전값, 새값, 전시점, 시점, 종류)
        SELECT N'토지특성', v.pnu, x.칼럼, x.전, x.새, v.py, v.base_year, N'바뀜'
          FROM v CROSS APPLY (VALUES (N'대장구분', p1, a1), (N'지목', p2, a2), (N'면적㎡', p3, a3), (N'용도지역', p4, a4),
                                     (N'이용상황', p6, a6), (N'지형높이', p7, a7), (N'지형형상', p8, a8), (N'도로접면', p9, a9)) x(칼럼, 전, 새)
         WHERE v.py IS NOT NULL
           AND (x.전 <> x.새 OR (x.전 IS NULL AND x.새 IS NOT NULL) OR (x.전 IS NOT NULL AND x.새 IS NULL));
        SET @n += @@ROWCOUNT;
        /* ② 정정 — 같은 필지·같은 연도의 옛 버전(is_current = 0) → 그다음 버전 */
        ;WITH h AS (
            SELECT pnu, base_year, valid_from,
                   a = (SELECT regstr_se_code AS c1, lndcgr_nm AS c2, CAST(lndpcl_ar AS DECIMAL(19,2)) AS c3, prpos_area1_nm AS c4, prpos_area2_nm AS c5,
                               lad_use_sittn_nm AS c6, tpgrph_hg_code_nm AS c7, tpgrph_frm_code_nm AS c8, road_side_code_nm AS c9, CAST(pblntf_pclnd AS DECIMAL(19,0)) AS c10 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES),
                   rn = ROW_NUMBER() OVER (PARTITION BY pnu, base_year ORDER BY valid_from)
              FROM silver.land_char lc WHERE lc.pnu LIKE @sgg + '%' AND (@prefix IS NULL OR lc.pnu LIKE @prefix + '%')
               AND EXISTS (SELECT 1 FROM silver.land_char z WHERE z.pnu = lc.pnu AND z.base_year = lc.base_year AND z.is_current = 0))
        INSERT gold.change_log (자료, 키, 칼럼, 전값, 새값, 전시점, 시점, 종류)
        SELECT N'토지특성', a.pnu, 이름.칼럼, oa.value, ob.value, a.base_year, a.base_year, N'정정'
          FROM h a JOIN h b ON b.pnu = a.pnu AND b.base_year = a.base_year AND b.rn = a.rn + 1
          CROSS APPLY OPENJSON(a.a) oa
          CROSS APPLY (SELECT value FROM OPENJSON(b.a) WHERE [key] = oa.[key]) ob
          CROSS APPLY (VALUES (CASE oa.[key] WHEN 'c1' THEN N'대장구분' WHEN 'c2' THEN N'지목' WHEN 'c3' THEN N'면적㎡' WHEN 'c4' THEN N'용도지역1' WHEN 'c5' THEN N'용도지역2'
                                              WHEN 'c6' THEN N'이용상황' WHEN 'c7' THEN N'지형높이' WHEN 'c8' THEN N'지형형상' WHEN 'c9' THEN N'도로접면' ELSE N'공시지가' END)) 이름(칼럼)
         WHERE ISNULL(oa.value, N'∅') <> ISNULL(ob.value, N'∅');
        SET @n += @@ROWCOUNT;
        COMMIT;
    END
    SELECT 줄 = @n, 초 = DATEDIFF(SECOND, @t0, SYSDATETIME());
END
GO
