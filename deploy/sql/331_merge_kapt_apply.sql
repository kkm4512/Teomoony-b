/* ============================================================
   331_merge_kapt_apply : 330 계획대로 K-apt 하나 = 대장 조각 여럿을 묶는다 (2026-10-23 사장님 "ㄱㄱ")
   ★ 묶는 방법은 287 과 **글자 그대로 같다**(지우지 않음 · 흡수 조각 행은 merged_into 로 남김 · 옮긴 것 전부 ops 기록 · 되돌리기 287 머리말).
     다른 것은 계획표(ops.complex_merge_plan_kapt)와 근거 글뿐.
   ★ 묶은 뒤 그 K-apt 를 남는 단지에 잇는다 — v_complex_kapt 셋째 길(ops.complex_merge_kapt 기록). 첫째·둘째 길이 이미 이은 K-apt·단지는 건드리지 않는다.
   ★ 뒤 계산: 실거래 요약(288) · 이름(285) · K-apt 표(280) · AI 요약표(314)는 따로 돌린다.
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
IF OBJECT_ID('ops.complex_merge_kapt') IS NULL
CREATE TABLE ops.complex_merge_kapt (
    kapt_code  VARCHAR(20)  NOT NULL CONSTRAINT pk_complex_merge_kapt PRIMARY KEY,
    new_id     INT          NOT NULL,
    조각       INT          NOT NULL,
    kapt_세대  INT          NULL,
    at         DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()
);
GO
EXEC gold.usp_plan_merge_kapt;
GO
/* ============ 적용 ============ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @t0 DATETIME2 = SYSDATETIME();

IF OBJECT_ID('tempdb..#mv') IS NOT NULL DROP TABLE #mv;
SELECT old_id = p.complex_id, new_id = p.남을코드, p.이름, p.세대, p.단지번호, p.kapt_code, p.kapt_이름
  INTO #mv
  FROM ops.complex_merge_plan_kapt p
  JOIN gold.complex c ON c.complex_id = p.complex_id AND c.merged_into IS NULL AND c.is_active = 1
  JOIN gold.complex s ON s.complex_id = p.남을코드 AND s.merged_into IS NULL AND s.is_active = 1
 WHERE p.판정 = N'묶음' AND p.complex_id <> p.남을코드;
CREATE CLUSTERED INDEX x ON #mv (old_id);

BEGIN TRAN;
    INSERT INTO ops.complex_merged (old_id, new_id, 이름, 세대, 단지번호, 근거)
    SELECT old_id, new_id, 이름, 세대, 단지번호, LEFT(N'K-apt 단지 하나(' + kapt_이름 + N') = 대장 조각 세대 합 · 같은 날 승인 (330)', 200) FROM #mv;
    /* K-apt 잇기의 근거 기록 — v_complex_kapt 셋째 길이 이 기록을 본다 */
    INSERT INTO ops.complex_merge_kapt (kapt_code, new_id, 조각, kapt_세대)
    SELECT p.kapt_code, p.남을코드, COUNT(*), MAX(p.kapt_세대)
      FROM ops.complex_merge_plan_kapt p WHERE p.판정 = N'묶음' AND p.남을코드 IN (SELECT new_id FROM #mv)
       AND NOT EXISTS (SELECT 1 FROM ops.complex_merge_kapt x WHERE x.kapt_code = p.kapt_code)
     GROUP BY p.kapt_code, p.남을코드;

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

/* ---- K-apt 길에 셋째 길(331)을 더한다 — 첫째·둘째 길은 317 과 글자 그대로 ---- */
CREATE OR ALTER VIEW gold.v_complex_kapt
AS
/* 279 첫째 길(그대로) */
WITH p AS (
    SELECT c.complex_id, c.hhld_cnt_sum, k.kapt_code, k.pnu,
           kh = COALESCE(NULLIF(k.hhld_cnt, 0), k.ho_cnt)
    FROM gold.complex c
    JOIN silver.kapt_complex k
      ON k.is_current = 1
     AND k.bjd_code = c.sigungu_cd + c.bjdong_cd
     AND k.kapt_usedate = c.oldest_use_apr
     AND NULLIF(k.kapt_usedate, '') IS NOT NULL
),
t1 AS (
    SELECT p.complex_id, p.kapt_code FROM p
     WHERE 1 = (SELECT COUNT(*) FROM p p2 WHERE p2.complex_id = p.complex_id)
       AND 1 = (SELECT COUNT(*) FROM p p3 WHERE p3.kapt_code  = p.kapt_code)
       /* 279: 지번도 세대도 안 맞으면 '거의 확실' 이 아니다 */
       AND NOT (p.pnu IS NOT NULL
                AND NOT EXISTS (SELECT 1 FROM gold.complex_pnu cp WHERE cp.complex_id = p.complex_id AND cp.pnu = p.pnu)
                AND (ISNULL(p.kh, 0) = 0 OR ABS(ISNULL(p.hhld_cnt_sum, 0) - p.kh) > 0.2 * p.kh))
),
/* 317 둘째 길: 도로명주소 + 건물번호 · 세대 5% 안 (gold.usp_refresh_kapt_road_link 가 만든 표) */
pr0 AS (
    SELECT complex_id, kapt_code FROM t1
    UNION ALL
    SELECT r.complex_id, r.kapt_code FROM gold.kapt_road_link r
),
/* 331 셋째 길: K-apt 하나 = 대장 조각 세대 합으로 묶은 단지(ops.complex_merge_kapt 기록) — 앞의 두 길이 안 쓴 K-apt·단지만 */
pr AS (
    SELECT complex_id, kapt_code FROM pr0
    UNION ALL
    SELECT m.new_id, m.kapt_code FROM ops.complex_merge_kapt m
      JOIN gold.complex c3 ON c3.complex_id = m.new_id AND c3.is_active = 1 AND c3.merged_into IS NULL
     WHERE NOT EXISTS (SELECT 1 FROM pr0 WHERE pr0.kapt_code = m.kapt_code)
       AND NOT EXISTS (SELECT 1 FROM pr0 WHERE pr0.complex_id = m.new_id)
)
SELECT pr.complex_id,
       k.kapt_code, k.kapt_name, k.kapt_addr, k.doro_juso,
       /* ★ hoCnt 는 호수, kaptdaCnt 가 세대수다(래미안퍼스트하이 호수 1,568 / 세대수 1,562 = 대장 1,562). */
       kapt_세대 = COALESCE(NULLIF(k.hhld_cnt, 0), k.ho_cnt),
       kapt_호수 = k.ho_cnt,       대장_세대 = c.hhld_cnt_sum,
       kapt_동수 = k.dong_cnt,     대장_동수 = c.dong_cnt,
       kapt_최고층 = k.top_floor,  대장_최고층 = c.max_floor,
       사용승인 = k.kapt_usedate,
       난방 = k.code_heat_nm, 복도 = k.code_hall_nm, 관리 = k.code_mgr_nm,
       분양임대 = k.code_sale_nm, 유형 = k.code_apt_nm,
       시공 = k.bcompany, 시행 = k.acompany,
       관리인원 = k.mgr_cnt,
       지하철 = k.subway_station, 지하철노선 = k.subway_line,
       지하철도보 = k.wtime_sub, 버스도보 = k.wtime_bus,
       /* ★ parking_cnt 에 kaptdaCnt(세대수)가 들어가 있었다 — 지상+지하 합을 쓴다 */
       주차 = ISNULL(k.parking_ground, 0) + ISNULL(k.parking_under, 0),
       주차_원본 = k.parking_cnt,
       주차_지상 = k.parking_ground, 주차_지하 = k.parking_under,
       전기차_지상 = k.el_charger_ground, 전기차_지하 = k.el_charger_under,
       CCTV = k.cctv_cnt,
       경비인원 = k.sec_cnt, 경비업체 = k.sec_company, 경비방식 = k.code_sec_nm,
       청소인원 = k.clean_cnt, 청소업체 = k.clean_company, 청소방식 = k.code_clean_nm,
       음식물 = k.code_garbage_nm, 소독 = k.code_disinf_nm, 승강기관리 = k.code_elev_nm,
       부대복리시설 = k.welfare_facility, 편의시설 = k.convenient_facility,
       교육시설 = k.education_facility,
       연면적 = k.kapt_tarea, 전용면적합 = k.priv_area
FROM pr
JOIN gold.complex c ON c.complex_id = pr.complex_id
JOIN silver.kapt_complex k ON k.kapt_code = pr.kapt_code AND k.is_current = 1;
GO
EXEC gold.usp_refresh_kapt_road_link;
GO
EXEC gold.usp_refresh_complex_kapt;
GO
SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT j = (SELECT m.kapt_code, k.kapt_name, m.new_id, m.조각, m.kapt_세대, 대장세대 = c.hhld_cnt_sum, 이어짐 = CASE WHEN x.kapt_code IS NULL THEN 0 ELSE 1 END
              FROM ops.complex_merge_kapt m JOIN gold.complex c ON c.complex_id = m.new_id
              JOIN silver.kapt_complex k ON k.kapt_code = m.kapt_code AND k.is_current = 1
              LEFT JOIN gold.complex_kapt x ON x.kapt_code = m.kapt_code AND x.complex_id = m.new_id FOR JSON PATH);
GO
