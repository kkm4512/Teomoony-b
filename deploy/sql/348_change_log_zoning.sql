/* 348 변경 로그 좁히기 (2026-10-24 17:58 사장님 "ㄱㄱ" — "그런 변경로그 데이터가 유의미해?" 에 대한 답)
   ★ 347 로 만든 토지특성 57만 줄 중 78% 가 **감정 칸**(지형형상 · 지형높이 · 도로접면 · 이용상황) — 땅이 바뀐 게 아니라 조사원이 해마다 다시 본 값
     (삼각형 → 부정형 1.6만, 되돌아간 것 6,786). '변화' 로 보이면 틀린 말이 된다 → 로그에서 뺀다(버전 행 silver.land_char 에는 다 그대로).
   ★ 지목 · 면적 · 대장구분 은 **토지이동이력**(silver.land_move_hist — 이동일 · 사유가 원문) 이 원본이다. 기준연도 비교로 또 만들면 같은 것이 둘(중복) → 뺀다.
   ★ 남는 것 = **용도지역**(1·2 를 한 묶음) 하나. 가치에 바로 닿고 원천에 따로 '이력' 이 없는 칸.
     · 'A → B' 다음 해에 'B → A' 로 되돌아간 쌍은 종류 = '흔들림'(조사 흔들림일 수 있다 — 화면 목차에 안 올린다). 표에는 남긴다. */
CREATE OR ALTER PROCEDURE gold.usp_change_log_land_char @prefix VARCHAR(10) = NULL
AS
BEGIN
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
        ;WITH s AS (
            SELECT pnu, base_year, valid_from, is_current,
                   z = CAST(CASE WHEN NULLIF(NULLIF(prpos_area1_nm, N'지정되지않음'), N'') IS NULL THEN ISNULL(NULLIF(NULLIF(prpos_area2_nm, N'지정되지않음'), N''), N'')
                               WHEN NULLIF(NULLIF(prpos_area2_nm, N'지정되지않음'), N'') IS NULL OR prpos_area2_nm = prpos_area1_nm THEN prpos_area1_nm
                               WHEN prpos_area1_nm < prpos_area2_nm THEN prpos_area1_nm + N' · ' + prpos_area2_nm
                               ELSE prpos_area2_nm + N' · ' + prpos_area1_nm END AS NVARCHAR(200))
              FROM silver.land_char WHERE pnu LIKE @sgg + '%' AND (@prefix IS NULL OR pnu LIKE @prefix + '%') AND base_year IS NOT NULL),
        v AS (SELECT pnu, base_year, z, py = LAG(base_year) OVER (PARTITION BY pnu ORDER BY base_year), pz = LAG(z) OVER (PARTITION BY pnu ORDER BY base_year)
                FROM s WHERE is_current = 1)
        INSERT gold.change_log (자료, 키, 칼럼, 전값, 새값, 전시점, 시점, 종류)
        SELECT N'토지특성', pnu, N'용도지역', NULLIF(pz, N''), NULLIF(z, N''), py, base_year, N'바뀜'
          FROM v WHERE py IS NOT NULL AND ISNULL(pz, N'') <> ISNULL(z, N'');
        SET @n += @@ROWCOUNT;
        /* 정정 — 같은 연도의 옛 버전 → 다음 버전에서 용도지역이 달라진 것 */
        ;WITH s AS (
            SELECT pnu, base_year, valid_from,
                   z = CAST(CASE WHEN NULLIF(NULLIF(prpos_area1_nm, N'지정되지않음'), N'') IS NULL THEN ISNULL(NULLIF(NULLIF(prpos_area2_nm, N'지정되지않음'), N''), N'')
                               WHEN NULLIF(NULLIF(prpos_area2_nm, N'지정되지않음'), N'') IS NULL OR prpos_area2_nm = prpos_area1_nm THEN prpos_area1_nm
                               WHEN prpos_area1_nm < prpos_area2_nm THEN prpos_area1_nm + N' · ' + prpos_area2_nm
                               ELSE prpos_area2_nm + N' · ' + prpos_area1_nm END AS NVARCHAR(200)),
                   rn = ROW_NUMBER() OVER (PARTITION BY pnu, base_year ORDER BY valid_from)
              FROM silver.land_char lc WHERE lc.pnu LIKE @sgg + '%' AND (@prefix IS NULL OR lc.pnu LIKE @prefix + '%')
               AND EXISTS (SELECT 1 FROM silver.land_char x WHERE x.pnu = lc.pnu AND x.base_year = lc.base_year AND x.is_current = 0))
        INSERT gold.change_log (자료, 키, 칼럼, 전값, 새값, 전시점, 시점, 종류)
        SELECT N'토지특성', a.pnu, N'용도지역', NULLIF(a.z, N''), NULLIF(b.z, N''), a.base_year, a.base_year, N'정정'
          FROM s a JOIN s b ON b.pnu = a.pnu AND b.base_year = a.base_year AND b.rn = a.rn + 1
         WHERE ISNULL(a.z, N'') <> ISNULL(b.z, N'');
        SET @n += @@ROWCOUNT;
        /* 흔들림 — A→B 바로 다음 바뀜이 B→A */
        UPDATE a SET 종류 = N'흔들림'
          FROM gold.change_log a
          JOIN gold.change_log b ON b.자료 = a.자료 AND b.키 = a.키 AND b.칼럼 = a.칼럼 AND b.종류 IN (N'바뀜', N'흔들림')
               AND ((b.전시점 = a.시점 AND ISNULL(b.새값, N'') = ISNULL(a.전값, N'') AND ISNULL(b.전값, N'') = ISNULL(a.새값, N''))
                 OR (a.전시점 = b.시점 AND ISNULL(a.새값, N'') = ISNULL(b.전값, N'') AND ISNULL(a.전값, N'') = ISNULL(b.새값, N'')))
         WHERE a.자료 = N'토지특성' AND a.종류 = N'바뀜' AND a.키 LIKE @sgg + '%';
        COMMIT;
    END
    SELECT 줄 = @n, 초 = DATEDIFF(SECOND, @t0, SYSDATETIME());
END
GO
