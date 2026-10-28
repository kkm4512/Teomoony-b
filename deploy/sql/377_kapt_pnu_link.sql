/* 377 (2026-10-28) K-apt 넷째 길(지번 + 사용승인일 + 세대 5%) · 둘째 길(도로명)의 시범 범위(서울·안양) 풀기 — 사장님 "2 ㄱㄱ"
   잰 것(_p_kapt · _p_kapt2): 미연결 5,844(오늘 묶음 뒤) 중 지번·날짜·세대 다 맞음 4,231 · 5% 안 하나씩 3,996(세대 똑같음 3,458).
   20% 는 1BL ↔ 2BL 이 붙어 버림 → 5%. 첫째 길 · 셋째 길은 그대로. */
SET QUOTED_IDENTIFIER ON; SET ANSI_NULLS ON;
GO
IF OBJECT_ID('gold.kapt_pnu_link') IS NULL
    CREATE TABLE gold.kapt_pnu_link (kapt_code VARCHAR(20) NOT NULL CONSTRAINT pk_kapt_pnu_link PRIMARY KEY, complex_id INT NOT NULL,
                                     kapt_세대 INT NULL, 대장_세대 INT NULL, 사용승인 CHAR(8) NULL, 굳힌시각 DATETIME2(0) NOT NULL DEFAULT SYSDATETIME());
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
    /* 377 넷째 길: K-apt 지번 = 단지 필지 + 사용승인일이 단지 범위 안 + 세대 5% 안 · 양쪽 하나씩 (gold.usp_refresh_kapt_pnu_link 가 만든 표) */
    UNION ALL
    SELECT p.complex_id, p.kapt_code FROM gold.kapt_pnu_link p
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
CREATE OR ALTER PROCEDURE gold.usp_refresh_kapt_pnu_link
AS
BEGIN
    /* 377 (2026-10-28 사장님 "2 ㄱㄱ" — K-apt 미연결 5,945곳): 미연결의 72%(4,231)가 **지번 · 사용승인일 · 세대가 다 맞는데** 안 이어져 있었다.
       첫째 길은 '같은 법정동 + 같은 사용승인일이 양쪽에 하나씩' 인데, 전국 단지 657만(작은 건물 전부)이 들어오며 같은 날 승인된 건물이 많아 '하나씩' 이 깨졌다.
       ★ 세 가지가 다 맞아야 한다(정책 3-7 '거의 확실'): K-apt 지번이 그 단지 필지 · K-apt 사용승인일이 그 단지 동들의 사용승인 범위 안 · 세대 5% 안.
       ★ 양쪽 하나씩만(K-apt 하나 ↔ 단지 하나). 20% 로 넓히면 한울마을 LH2단지 1BL 이 2BL 에 붙는다(1,400 ↔ 1,196) — 5% (둘째 길과 같은 문턱).
       ★ 이미 다른 길로 이어진 K-apt · 단지는 건드리지 않는다. 이름은 안 본다. */
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @t DATETIME2 = SYSDATETIME();
    IF OBJECT_ID('gold.kapt_pnu_link') IS NULL
        CREATE TABLE gold.kapt_pnu_link (kapt_code VARCHAR(20) NOT NULL CONSTRAINT pk_kapt_pnu_link PRIMARY KEY, complex_id INT NOT NULL,
                                         kapt_세대 INT NULL, 대장_세대 INT NULL, 사용승인 CHAR(8) NULL, 굳힌시각 DATETIME2(0) NOT NULL DEFAULT SYSDATETIME());
    DELETE FROM gold.kapt_pnu_link;                    /* 파생 — 아래에서 다시 만든다(뷰가 이 표를 읽으므로 먼저 비우고 남은 길과 견준다) */
    SELECT complex_id, kapt_code INTO #t1 FROM gold.v_complex_kapt;
    SELECT k.kapt_code, c.complex_id, kh = COALESCE(NULLIF(k.hhld_cnt, 0), k.ho_cnt), c.hhld_cnt_sum, k.kapt_usedate
      INTO #m
      FROM silver.kapt_complex k
      JOIN gold.complex_pnu cp ON cp.pnu = k.pnu
      JOIN gold.complex c ON c.complex_id = cp.complex_id AND c.is_active = 1 AND c.merged_into IS NULL AND c.hhld_cnt_sum > 0
     WHERE k.is_current = 1 AND COALESCE(NULLIF(k.hhld_cnt, 0), k.ho_cnt) > 0 AND LEN(k.kapt_usedate) = 8
       AND k.kapt_usedate BETWEEN c.oldest_use_apr AND ISNULL(c.latest_use_apr, c.oldest_use_apr)
       AND ABS(c.hhld_cnt_sum - COALESCE(NULLIF(k.hhld_cnt, 0), k.ho_cnt)) <= 0.05 * COALESCE(NULLIF(k.hhld_cnt, 0), k.ho_cnt)
       AND NOT EXISTS (SELECT 1 FROM #t1 t WHERE t.kapt_code = k.kapt_code)
       AND NOT EXISTS (SELECT 1 FROM #t1 t WHERE t.complex_id = c.complex_id);
    INSERT INTO gold.kapt_pnu_link (kapt_code, complex_id, kapt_세대, 대장_세대, 사용승인)
    SELECT m.kapt_code, MIN(m.complex_id), MIN(m.kh), MIN(m.hhld_cnt_sum), MIN(m.kapt_usedate)
      FROM #m m
     WHERE 1 = (SELECT COUNT(DISTINCT m2.complex_id) FROM #m m2 WHERE m2.kapt_code = m.kapt_code)
       AND 1 = (SELECT COUNT(DISTINCT m3.kapt_code) FROM #m m3 WHERE m3.complex_id = m.complex_id)
     GROUP BY m.kapt_code;
    SELECT 넷째길 = (SELECT COUNT(*) FROM gold.kapt_pnu_link), 초 = DATEDIFF(SECOND, @t, SYSDATETIME());
END
GO
CREATE OR ALTER PROCEDURE gold.usp_refresh_kapt_road_link
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @t DATETIME2 = SYSDATETIME();
    /* K-apt → 공식 코드 */
    IF OBJECT_ID('tempdb..#k') IS NOT NULL DROP TABLE #k;
    SELECT k.kapt_code, 세대 = COALESCE(NULLIF(k.hhld_cnt, 0), k.ho_cnt), e.rn_mgt_sn, e.buld_mnnm, e.buld_slno, e.pnu, 주소 = e.keyword
      INTO #k FROM silver.kapt_complex k
      JOIN gold.v_juso_exact e ON e.keyword = CAST(LTRIM(RTRIM(LEFT(k.doro_juso, PATINDEX('%[0-9] %', k.doro_juso + ' ')))) AS NVARCHAR(300))
     WHERE k.is_current = 1 AND COALESCE(NULLIF(k.hhld_cnt, 0), k.ho_cnt) > 0;
    /* 대장 동 → 도로명코드 · 건물번호 */
    IF OBJECT_ID('tempdb..#b') IS NOT NULL DROP TABLE #b;
    SELECT DISTINCT b.na_road_cd, bm = TRY_CAST(b.na_main_bun AS INT), bs = ISNULL(TRY_CAST(b.na_sub_bun AS INT), 0), cb.complex_id
      INTO #b FROM silver.bld_title b JOIN gold.complex_bld cb ON cb.mgm_bldrgst_pk = b.mgm_bldrgst_pk
     WHERE b.is_current = 1 AND b.na_road_cd IS NOT NULL AND ISNULL(b.na_ugrnd_cd, '0') = '0'
;   /* 377: 서울 · 안양(시범 범위)에만 걸려 있던 것을 푼다 — 전국 대장 */
    CREATE INDEX ix ON #b (na_road_cd, bm, bs);
    BEGIN TRAN;
        DELETE FROM gold.kapt_road_link;                          /* 파생 — 이제 뷰는 첫째 길만 */
        SELECT complex_id, kapt_code INTO #t1 FROM gold.v_complex_kapt;
        SELECT k.kapt_code, c.complex_id, k.주소, k.세대, c.hhld_cnt_sum, 근거 = CAST(x.근거 AS NVARCHAR(40))
          INTO #m
          FROM #k k
          CROSS APPLY (SELECT b.complex_id, 근거 = N'도로명코드' FROM #b b WHERE b.na_road_cd = k.rn_mgt_sn AND b.bm = k.buld_mnnm AND b.bs = ISNULL(k.buld_slno, 0)
                       UNION SELECT cp.complex_id, N'공식 지번' FROM gold.complex_pnu cp WHERE cp.pnu = k.pnu) x
          JOIN gold.complex c ON c.complex_id = x.complex_id AND c.is_active = 1 AND c.merged_into IS NULL AND c.hhld_cnt_sum > 0
         WHERE ABS(c.hhld_cnt_sum - k.세대) <= 0.05 * k.세대
           AND NOT EXISTS (SELECT 1 FROM #t1 t WHERE t.kapt_code = k.kapt_code)
           AND NOT EXISTS (SELECT 1 FROM #t1 t WHERE t.complex_id = c.complex_id);
        INSERT INTO gold.kapt_road_link (kapt_code, complex_id, 주소, kapt_세대, 대장_세대, 근거)
        SELECT m.kapt_code, m.complex_id, MIN(m.주소), MIN(m.세대), MIN(m.hhld_cnt_sum),
               근거 = CASE WHEN COUNT(DISTINCT m.근거) > 1 THEN N'도로명코드 + 공식 지번' ELSE MIN(m.근거) END
          FROM #m m
         WHERE 1 = (SELECT COUNT(DISTINCT m2.complex_id) FROM #m m2 WHERE m2.kapt_code = m.kapt_code)
           AND 1 = (SELECT COUNT(DISTINCT m3.kapt_code)  FROM #m m3 WHERE m3.complex_id = m.complex_id)
         GROUP BY m.kapt_code, m.complex_id;
    COMMIT;
    SELECT 둘째길 = (SELECT COUNT(*) FROM gold.kapt_road_link), 초 = DATEDIFF(SECOND, @t, SYSDATETIME());
END
GO
CREATE OR ALTER PROCEDURE gold.usp_refresh_complex_kapt
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @t DATETIME2 = SYSDATETIME();
    EXEC gold.usp_refresh_kapt_road_link;                   /* 317: 둘째 길 먼저 */
    EXEC gold.usp_refresh_kapt_pnu_link;                    /* 377: 넷째 길(지번 + 사용승인일 + 세대 5%) */
    SELECT * INTO #v FROM gold.v_complex_kapt;          /* 무거운 계산은 트랜잭션 밖에서 */
    BEGIN TRAN;
        DELETE FROM gold.complex_kapt;
        INSERT INTO gold.complex_kapt SELECT v.*, SYSDATETIME() FROM #v v;
    COMMIT;
    SELECT 연결 = (SELECT COUNT(*) FROM gold.complex_kapt), 초 = DATEDIFF(SECOND, @t, SYSDATETIME());
END
GO
EXEC gold.usp_refresh_complex_kapt;
GO
SELECT 길 = N'넷째(지번+날짜+세대)', n = COUNT(*) FROM gold.kapt_pnu_link UNION ALL SELECT N'둘째(도로명)', COUNT(*) FROM gold.kapt_road_link UNION ALL SELECT N'전체 연결 K-apt', COUNT(DISTINCT kapt_code) FROM gold.complex_kapt UNION ALL SELECT N'지금 K-apt', COUNT(*) FROM silver.kapt_complex WHERE is_current = 1;
