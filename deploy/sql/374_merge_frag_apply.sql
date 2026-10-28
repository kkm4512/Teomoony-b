/* ============================================================
   374_merge_frag_apply : 373 계획(ops.complex_merge_plan_frag · 판정 '묶음')대로 총괄표제부 없는 대장 조각을 묶는다 (2026-10-28 사장님 "A ㄱㄱ")
   ★ 묶는 방법은 287 · 331 과 **글자 그대로 같다** — 지우지 않음(흡수 조각 행은 merged_into 로 남김) · 옮긴 것 전부 ops.complex_merged / ops.complex_merge_moves
     · 되돌리기는 287 머리말 · 다시 지어도 유지(흡수 조각의 대장 식별자가 남는 코드를 가리킴).
   ★ 뒤 계산: 실거래 요약(288) · 이름(285) · AI 요약표(314) — 이 파일 끝에서 실거래 요약 · 이름은 바로 돌린다.
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* ============ 적용 ============ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @t0 DATETIME2 = SYSDATETIME();

IF OBJECT_ID('tempdb..#mv') IS NOT NULL DROP TABLE #mv;
SELECT old_id = p.complex_id, new_id = p.남을코드, p.이름, p.세대, 단지번호 = CAST(NULL AS NVARCHAR(200)), p.근거
  INTO #mv
  FROM ops.complex_merge_plan_frag p
  JOIN gold.complex c ON c.complex_id = p.complex_id AND c.merged_into IS NULL AND c.is_active = 1
  JOIN gold.complex s ON s.complex_id = p.남을코드 AND s.merged_into IS NULL AND s.is_active = 1
 WHERE p.판정 = N'묶음' AND p.complex_id <> p.남을코드;
CREATE CLUSTERED INDEX x ON #mv (old_id);

BEGIN TRAN;
    INSERT INTO ops.complex_merged (old_id, new_id, 이름, 세대, 단지번호, 근거)
    SELECT old_id, new_id, 이름, 세대, 단지번호, 근거 FROM #mv;
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

EXEC gold.usp_refresh_complex_trade;
GO
EXEC gold.usp_refresh_complex_alias;
GO
SELECT 남은조각단지 = COUNT(*) FROM gold.complex WHERE complex_id BETWEEN 722419 AND 722429 AND merged_into IS NULL;
SELECT complex_id, complex_nm, dong_cnt, hhld_cnt_sum, trade_cnt, rent_cnt FROM gold.complex WHERE complex_id = 722419;
