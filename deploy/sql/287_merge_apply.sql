/* ============================================================
   287_merge_apply : 286 계획대로 쪼개진 단지 조각을 묶는다 (2026-10-21 18:03 사장님 "ㄱㄱ")
   뒷줄 작업 aa-merge-bg 로 돈다(286 을 다시 계산한 뒤 적용).

   ★ 지우지 않는다(원본 훼손 금지)
     · 흡수된 조각 행은 gold.complex 에 **남는다** — merged_into = 남는 코드, is_active = 0,
       지도 좌표·대표지번·요약을 비운다(동·필지가 더는 없으므로 그게 사실이다).
     · 옮긴 것은 전부 기록: ops.complex_merged(옛→새) · ops.complex_merge_moves(필지·식별자·거래).
     · 되돌리기는 이 기록으로 가능하다(머리말 끝).
     · complex_pnu 의 흡수 조각 행은 지운다 — 파생 연결표(빌드가 만든다)이고 옮긴 기록이 남는다.
   ★ 재구성해도 유지된다: 흡수 조각의 대장 식별자(ROOT_PK)가 남는 코드를 가리키고(is_primary=0),
     usp_resolve_complex 는 is_primary=0 이면 이름을 덮지 않는다(아래에서 고침).
   ★ 다시 계산: 남는 단지만 — 빌드와 같은 요약 규칙 · usp_refresh_complex_geo/building(@complex_id).
     실거래 건수는 바로 뒤 ab-tradepick-bg(283) 의 usp_refresh_complex_trade 가 다시 센다.
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
IF COL_LENGTH('gold.complex', 'merged_into') IS NULL
    ALTER TABLE gold.complex ADD merged_into INT NULL;
GO
IF OBJECT_ID('ops.complex_merged') IS NULL
CREATE TABLE ops.complex_merged (
    old_id    INT           NOT NULL CONSTRAINT pk_complex_merged PRIMARY KEY,
    new_id    INT           NOT NULL,
    이름      NVARCHAR(200) NULL,
    세대      INT           NULL,
    단지번호  NVARCHAR(200) NULL,
    근거      NVARCHAR(200) NOT NULL,
    at        DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);
IF OBJECT_ID('ops.complex_merge_moves') IS NULL
CREATE TABLE ops.complex_merge_moves (
    move_sk   BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT pk_complex_merge_moves PRIMARY KEY,
    old_id    INT          NOT NULL,
    new_id    INT          NOT NULL,
    무엇      VARCHAR(20)  NOT NULL,      -- pnu | identity | bld | trade
    값        VARCHAR(100) NOT NULL,      -- pnu / identity_sk / mgm_bldrgst_pk / trade_sk
    옛값      VARCHAR(100) NULL,          -- pnu_role / is_primary 등
    at        DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()
);
GO

/* ---- 재구성 때 흡수 조각 이름이 남는 단지 이름을 덮지 않게 ---- */
CREATE OR ALTER PROCEDURE gold.usp_resolve_complex
    @identity_type  VARCHAR(20),
    @identity_val   VARCHAR(100),
    @complex_nm     NVARCHAR(200) = NULL,
    @complex_nm_src VARCHAR(10)   = NULL,   -- RECAP | TITLE | GENERAL | ADDR
    @sigungu_cd     CHAR(5)       = NULL,
    @bjdong_cd      CHAR(5)       = NULL,
    @grouping_rule  VARCHAR(30)   = NULL,
    @root_pk        VARCHAR(50)   = NULL,
    @complex_id     INT           OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /* ★ OUTPUT 변수는 호출자의 직전 값을 들고 들어온다.
       SELECT @x = ... 는 행이 없으면 변수를 그대로 둔다(NULL 로 만들지 않는다).
       초기화하지 않으면 두 번째 호출부터 직전 단지를 재사용해버린다. */
    SET @complex_id = NULL;
    DECLARE @primary BIT = NULL;

    SELECT @complex_id = complex_id, @primary = is_primary
    FROM gold.complex_identity
    WHERE identity_type = @identity_type AND identity_val = @identity_val;

    IF @complex_id IS NOT NULL
    BEGIN
        /* ★ 2026-10-21 (287): 묶여 들어온 조각의 식별자(is_primary=0)는 이름을 **덮지 않는다** —
           안 그러면 재구성할 때마다 남는 단지 이름이 조각 이름('`' 같은 것)으로 바뀐다. */
        IF @primary = 0 RETURN;
        /* ★ 이름 덮어쓰기 규칙
           예전에는 COALESCE(@complex_nm, complex_nm) 이라, 한 번 주소가 들어가면
           진짜 이름이 나중에 생겨도 영영 안 바뀌었다. 출처를 기록해 두고
           '주소였던 것' 은 비워서 끝의 폴백이 다시 돌게 한다. */
        UPDATE gold.complex
           SET complex_nm = CASE WHEN @complex_nm IS NOT NULL   THEN @complex_nm
                                 WHEN complex_nm_src = 'ADDR'   THEN NULL
                                 ELSE complex_nm END,
               complex_nm_src = CASE WHEN @complex_nm IS NOT NULL THEN @complex_nm_src
                                     WHEN complex_nm_src = 'ADDR' THEN NULL
                                     ELSE complex_nm_src END,
               updated_at = SYSDATETIME()
         WHERE complex_id = @complex_id;
        RETURN;
    END

    BEGIN TRAN;
        INSERT INTO gold.complex (root_bldrgst_pk, complex_nm, complex_nm_src,
                                   sigungu_cd, bjdong_cd, grouping_rule)
        VALUES (@root_pk, @complex_nm, @complex_nm_src, @sigungu_cd, @bjdong_cd, @grouping_rule);
        SET @complex_id = CAST(SCOPE_IDENTITY() AS INT);

        INSERT INTO gold.complex_identity (complex_id, identity_type, identity_val, is_primary)
        VALUES (@complex_id, @identity_type, @identity_val, 1);
    COMMIT;
END
GO

/* ---- 남는 단지만 다시 계산할 수 있게 (@complex_id = NULL 이면 전과 똑같이 전체) ---- */
CREATE OR ALTER PROCEDURE gold.usp_refresh_complex_geo
    @complex_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    WITH g AS (
        SELECT cp.complex_id,
               MIN(p.bbox_minx) AS minx, MIN(p.bbox_miny) AS miny,
               MAX(p.bbox_maxx) AS maxx, MAX(p.bbox_maxy) AS maxy,
               AVG(p.jiga)      AS jiga_avg,
               COUNT(p.pnu)     AS hit
        FROM gold.complex_pnu cp
        JOIN silver.cadastral_parcel p ON p.pnu = cp.pnu AND p.is_current = 1
        WHERE (@complex_id IS NULL OR cp.complex_id = @complex_id)
        GROUP BY cp.complex_id
    )
    UPDATE c
       SET c.bbox_minx = g.minx, c.bbox_miny = g.miny,
           c.bbox_maxx = g.maxx, c.bbox_maxy = g.maxy,
           c.centroid_lng = CAST((g.minx + g.maxx) / 2 AS DECIMAL(10,7)),
           c.centroid_lat = CAST((g.miny + g.maxy) / 2 AS DECIMAL(10,7)),
           c.jiga_avg   = g.jiga_avg,
           c.parcel_hit = g.hit,
           c.updated_at = SYSDATETIME()
      FROM gold.complex c JOIN g ON g.complex_id = c.complex_id;
END
GO
CREATE OR ALTER PROCEDURE gold.usp_refresh_complex_building
    @complex_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    /* 화면(server.js /api/complexes/:id/buildings)과 같은 조인이다.
       bbox 로 먼저 거르고 STIntersects 로 확정한다. */
    WITH b AS (
        SELECT cp.complex_id,
               bld_cnt   = COUNT(DISTINCT f.bd_mgt_sn),
               max_floor = MAX(f.gro_flo_co)
          FROM gold.complex_pnu cp
          JOIN silver.cadastral_parcel p
            ON p.pnu = cp.pnu AND p.is_current = 1 AND p.geom IS NOT NULL
          JOIN silver.building_footprint f
            ON f.is_current = 1 AND f.geom IS NOT NULL
           AND f.bbox_minx <= p.bbox_maxx AND f.bbox_maxx >= p.bbox_minx
           AND f.bbox_miny <= p.bbox_maxy AND f.bbox_maxy >= p.bbox_miny
           AND f.geom.STIntersects(p.geom) = 1
         WHERE (@complex_id IS NULL OR cp.complex_id = @complex_id)
         GROUP BY cp.complex_id
    )
    UPDATE c
       SET c.bld_cnt    = ISNULL(b.bld_cnt, 0),
           c.max_floor  = b.max_floor,
           c.updated_at = SYSDATETIME()
      FROM gold.complex c
      LEFT JOIN b ON b.complex_id = c.complex_id
     WHERE EXISTS (SELECT 1 FROM gold.complex_pnu cp WHERE cp.complex_id = c.complex_id)
       AND (@complex_id IS NULL OR c.complex_id = @complex_id);
END
GO

/* ---- 지도·목록에서 흡수 조각을 뺀다 (뷰 정의는 그대로 + 한 줄) ---- */
CREATE OR ALTER VIEW gold.v_complex_map
AS
SELECT
    c.complex_id, c.complex_nm, c.grouping_rule, c.has_recap,
    c.sigungu_cd, c.bjdong_cd, l.full_nm AS lawd_nm,
    c.rep_pnu, meta.fn_pnu_to_jibun(c.rep_pnu) AS rep_jibun,
    c.rep_plat_plc, c.rep_road_addr,
    c.dong_cnt, c.bld_cnt, c.max_floor,
    c.pnu_cnt, c.parcel_hit,
    c.hhld_cnt_sum, c.tot_area_sum,
    c.oldest_use_apr, c.latest_use_apr, c.jiga_avg,
    c.trade_cnt, c.rent_cnt, c.trade_last_ymd, c.trade_last_amt, c.trade_avg_unit,
    c.centroid_lat, c.centroid_lng,
    c.bbox_minx, c.bbox_miny, c.bbox_maxx, c.bbox_maxy
FROM gold.complex c
LEFT JOIN meta.lawd_code l ON l.lawd_cd = LEFT(c.rep_pnu,10)
WHERE c.merged_into IS NULL;      -- ★ 287: 묶여 들어간 조각은 안 보인다
GO

/* ============ 적용 ============ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @t0 DATETIME2 = SYSDATETIME();

IF OBJECT_ID('tempdb..#mv') IS NOT NULL DROP TABLE #mv;
SELECT old_id = p.complex_id, new_id = p.남을코드, p.이름, p.세대, p.단지번호
  INTO #mv
  FROM ops.complex_merge_plan p
  JOIN gold.complex c ON c.complex_id = p.complex_id AND c.merged_into IS NULL
 WHERE p.판정 = N'묶음' AND p.남을코드 IS NOT NULL AND p.complex_id <> p.남을코드;
CREATE CLUSTERED INDEX x ON #mv (old_id);

BEGIN TRAN;
    INSERT INTO ops.complex_merged (old_id, new_id, 이름, 세대, 단지번호, 근거)
    SELECT old_id, new_id, 이름, 세대, 단지번호, N'같은 필지 · 주택 동 · 단지번호 하나 (286)' FROM #mv;

    /* 필지 */
    INSERT INTO ops.complex_merge_moves (old_id, new_id, 무엇, 값, 옛값)
    SELECT m.old_id, m.new_id, 'pnu', cp.pnu, cp.pnu_role FROM #mv m JOIN gold.complex_pnu cp ON cp.complex_id = m.old_id;
    UPDATE s SET s.pnu_role = 'MAIN'
      FROM gold.complex_pnu s JOIN #mv m ON m.new_id = s.complex_id
      JOIN gold.complex_pnu o ON o.complex_id = m.old_id AND o.pnu = s.pnu
     WHERE o.pnu_role = 'MAIN' AND ISNULL(s.pnu_role, '') <> 'MAIN';
    INSERT INTO gold.complex_pnu (complex_id, pnu, pnu_role)
    SELECT m.new_id, o.pnu, MAX(o.pnu_role)
      FROM #mv m JOIN gold.complex_pnu o ON o.complex_id = m.old_id
     WHERE NOT EXISTS (SELECT 1 FROM gold.complex_pnu s WHERE s.complex_id = m.new_id AND s.pnu = o.pnu)
     GROUP BY m.new_id, o.pnu;
    DELETE cp FROM gold.complex_pnu cp JOIN #mv m ON m.old_id = cp.complex_id;

    /* 동(대장) */
    INSERT INTO ops.complex_merge_moves (old_id, new_id, 무엇, 값)
    SELECT m.old_id, m.new_id, 'bld', cb.mgm_bldrgst_pk FROM #mv m JOIN gold.complex_bld cb ON cb.complex_id = m.old_id;
    UPDATE cb SET cb.complex_id = m.new_id FROM gold.complex_bld cb JOIN #mv m ON m.old_id = cb.complex_id;

    /* 식별자 — 남는 코드를 가리키되 주 식별자는 아니다 */
    INSERT INTO ops.complex_merge_moves (old_id, new_id, 무엇, 값, 옛값)
    SELECT m.old_id, m.new_id, 'identity', CAST(i.identity_sk AS VARCHAR(100)), CAST(i.is_primary AS VARCHAR(5))
      FROM #mv m JOIN gold.complex_identity i ON i.complex_id = m.old_id;
    UPDATE i SET i.complex_id = m.new_id, i.is_primary = 0 FROM gold.complex_identity i JOIN #mv m ON m.old_id = i.complex_id;

    /* 실거래 연결 */
    INSERT INTO ops.complex_merge_moves (old_id, new_id, 무엇, 값)
    SELECT m.old_id, m.new_id, 'trade', CAST(t.trade_sk AS VARCHAR(100)) FROM #mv m JOIN silver.rtms_trade t ON t.match_complex_id = m.old_id;
    UPDATE t SET t.match_complex_id = m.new_id FROM silver.rtms_trade t JOIN #mv m ON m.old_id = t.match_complex_id;

    /* 흡수 조각 — 남기되 비운다 */
    UPDATE c SET c.merged_into = m.new_id, c.is_active = 0,
                 c.rep_pnu = NULL, c.centroid_lat = NULL, c.centroid_lng = NULL,
                 c.bbox_minx = NULL, c.bbox_miny = NULL, c.bbox_maxx = NULL, c.bbox_maxy = NULL,
                 c.dong_cnt = 0, c.pnu_cnt = 0, c.hhld_cnt_sum = NULL, c.tot_area_sum = NULL,
                 c.oldest_use_apr = NULL, c.latest_use_apr = NULL,   -- 날짜로 잇는 길(v_complex_kapt 등)에 안 걸리게
                 c.trade_cnt = NULL, c.rent_cnt = NULL, c.trade_last_ymd = NULL, c.trade_last_amt = NULL,
                 c.trade_avg_unit = NULL, c.bld_cnt = NULL, c.max_floor = NULL, c.parcel_hit = NULL,
                 c.updated_at = SYSDATETIME()
      FROM gold.complex c JOIN #mv m ON m.old_id = c.complex_id;
COMMIT;

/* ---- 남는 단지 요약 — usp_build_complexes 와 같은 규칙 ---- */
IF OBJECT_ID('tempdb..#sv') IS NOT NULL DROP TABLE #sv;
SELECT DISTINCT complex_id = new_id INTO #sv FROM #mv;
WITH agg AS (
    SELECT cb.complex_id,
           SUM(CASE WHEN cb.regstr_kind_cd IN ('2','3') THEN 1 ELSE 0 END) AS dong_cnt,
           MAX(CASE WHEN cb.is_recap = 1 THEN 1 ELSE 0 END)                AS has_recap
    FROM gold.complex_bld cb WHERE cb.complex_id IN (SELECT complex_id FROM #sv) GROUP BY cb.complex_id
), tagg AS (
    SELECT cb.complex_id,
           SUM(t.hhld_cnt) AS hhld_sum, SUM(t.tot_area) AS area_sum,
           MIN(NULLIF(t.use_apr_day,'')) AS min_apr, MAX(NULLIF(t.use_apr_day,'')) AS max_apr
    FROM gold.complex_bld cb
    JOIN silver.bld_title t ON t.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND t.is_current = 1
    WHERE cb.complex_id IN (SELECT complex_id FROM #sv)
    GROUP BY cb.complex_id
), pnuagg AS (
    SELECT complex_id, COUNT(*) AS pnu_cnt FROM gold.complex_pnu WHERE complex_id IN (SELECT complex_id FROM #sv) GROUP BY complex_id
), rep AS (
    SELECT cb.complex_id, b.pnu, b.plat_plc, b.new_plat_plc,
           ROW_NUMBER() OVER (PARTITION BY cb.complex_id
               ORDER BY cb.is_recap DESC, ISNULL(t.tot_area,0) DESC, b.mgm_bldrgst_pk) AS rn
    FROM gold.complex_bld cb
    JOIN silver.bld_basis_outline b ON b.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND b.is_current = 1
    LEFT JOIN silver.bld_title t    ON t.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND t.is_current = 1
    WHERE cb.complex_id IN (SELECT complex_id FROM #sv)
)
UPDATE c
   SET c.dong_cnt       = a.dong_cnt,
       c.has_recap      = a.has_recap,
       c.pnu_cnt        = p.pnu_cnt,
       c.hhld_cnt_sum   = tg.hhld_sum,
       c.tot_area_sum   = tg.area_sum,
       c.oldest_use_apr = tg.min_apr,
       c.latest_use_apr = tg.max_apr,
       c.rep_pnu        = COALESCE(r.pnu, c.rep_pnu),
       c.rep_plat_plc   = COALESCE(r.plat_plc, c.rep_plat_plc),
       c.rep_road_addr  = COALESCE(r.new_plat_plc, c.rep_road_addr),
       c.updated_at     = SYSDATETIME()
  FROM gold.complex c
  JOIN agg a         ON a.complex_id  = c.complex_id
  LEFT JOIN tagg tg  ON tg.complex_id = c.complex_id
  LEFT JOIN pnuagg p ON p.complex_id  = c.complex_id
  LEFT JOIN rep r    ON r.complex_id  = c.complex_id AND r.rn = 1;

UPDATE cp SET is_representative = CASE WHEN cp.pnu = c.rep_pnu THEN 1 ELSE 0 END
  FROM gold.complex_pnu cp JOIN gold.complex c ON c.complex_id = cp.complex_id
 WHERE cp.complex_id IN (SELECT complex_id FROM #sv);

DECLARE @id INT;
DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT complex_id FROM #sv;
OPEN cur; FETCH NEXT FROM cur INTO @id;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC gold.usp_refresh_complex_geo @complex_id = @id;
    EXEC gold.usp_refresh_complex_building @complex_id = @id;
    FETCH NEXT FROM cur INTO @id;
END
CLOSE cur; DEALLOCATE cur;

SELECT 흡수 = (SELECT COUNT(*) FROM #mv), 남는단지 = (SELECT COUNT(*) FROM #sv),
       옮긴필지 = (SELECT COUNT(*) FROM ops.complex_merge_moves WHERE 무엇 = 'pnu' AND old_id IN (SELECT old_id FROM #mv)),
       옮긴거래 = (SELECT COUNT(*) FROM ops.complex_merge_moves WHERE 무엇 = 'trade' AND old_id IN (SELECT old_id FROM #mv)),
       초 = DATEDIFF(SECOND, @t0, SYSDATETIME());
GO
EXEC gold.usp_refresh_complex_kapt;
GO
SET NOCOUNT ON;
SELECT c.complex_id, c.complex_nm, c.dong_cnt, c.hhld_cnt_sum, c.pnu_cnt, c.centroid_lat
  FROM gold.complex c WHERE c.complex_id IN (298577, 288357, 162250, 357427);
GO
/* 되돌리기(필요할 때만, 손으로):
   1) UPDATE gold.complex_identity SET complex_id = m.old_id, is_primary = CAST(m.옛값 AS BIT)
        FROM gold.complex_identity i JOIN ops.complex_merge_moves m ON m.무엇 = 'identity' AND CAST(m.값 AS BIGINT) = i.identity_sk;
   2) complex_bld · rtms_trade 도 같은 식(무엇 = 'bld' / 'trade').
   3) INSERT complex_pnu (old_id, pnu, 옛값) ← 무엇 = 'pnu' · 남는 쪽에 새로 넣은 필지는 빼기.
   4) UPDATE gold.complex SET merged_into = NULL, is_active = 1 WHERE complex_id IN (SELECT old_id FROM ops.complex_merged);
      그리고 usp_build_complexes 로 요약 재계산. */
