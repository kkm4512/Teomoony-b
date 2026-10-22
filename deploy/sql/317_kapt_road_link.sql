/* ============================================================
   317_kapt_road_link : K-apt ↔ 단지 둘째 길 — **도로명주소 + 건물번호가 같고 세대가 5% 안** (2026-10-23 새벽, 사장님 "확실한건만 매칭 기준을 정리해")
   ★ 왜(실측): K-apt 3,410 중 단지에 안 이어진 것 1,458(서울·안양). 첫째 길(같은 법정동 + 같은 사용승인일이 양쪽에 하나씩)은
     같은 동 · 같은 날 승인 단지가 둘이면 아무것도 안 잇는다 — 파크리오 · 잠실엘스 · 리센츠 · 반포자이 · 메이플자이 · 올림픽파크포레온도 안 이어져 있었다.
   ★ 규칙(이름은 안 본다):
       K-apt 도로명주소(doroJuso)의 '시도 시군구 도로명 건물번호' = 그 단지 어느 동의 대장 도로명주소(new_plat_plc, 괄호 앞)
       + 세대가 5% 안(K-apt 세대수 > 0)
       + 그 K-apt 에 맞는 단지가 **하나**, 그 단지에 맞는 K-apt 가 **하나**
       + 첫째 길로 이미 이어진 K-apt · 단지는 건드리지 않는다
   ★ 표(gold.kapt_road_link)는 파생 — 갱신 때 지우고 다시 만든다(작업방식 7장 예외). 뷰 gold.v_complex_kapt 가 첫째 길 ∪ 이 표.
     gold.complex_kapt(굳힌 표)는 예전대로 usp_refresh_complex_kapt 가 뷰를 굳힌다 — 그 앞에서 이 표를 먼저 만든다.
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
IF OBJECT_ID('gold.kapt_road_link') IS NULL
CREATE TABLE gold.kapt_road_link (
    kapt_code   VARCHAR(20)   NOT NULL CONSTRAINT pk_kapt_road_link PRIMARY KEY,
    complex_id  INT           NOT NULL,
    주소        NVARCHAR(200) NOT NULL,
    kapt_세대   INT           NULL,
    대장_세대   INT           NULL,
    굳힌시각    DATETIME2(0)  NOT NULL CONSTRAINT df_kapt_road_link_t DEFAULT SYSDATETIME()
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'uq_kapt_road_link_c' AND object_id = OBJECT_ID('gold.kapt_road_link'))
    CREATE UNIQUE INDEX uq_kapt_road_link_c ON gold.kapt_road_link (complex_id);
GO
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
pr AS (
    SELECT complex_id, kapt_code FROM t1
    UNION ALL
    SELECT r.complex_id, r.kapt_code FROM gold.kapt_road_link r
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
CREATE OR ALTER PROCEDURE gold.usp_refresh_kapt_road_link
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @t DATETIME2 = SYSDATETIME();
    /* K-apt: '시도 시군구 도로명 건물번호' — 첫 '숫자+빈칸' 까지(뒤의 단지 이름 · 괄호를 자른다) */
    IF OBJECT_ID('tempdb..#k') IS NOT NULL DROP TABLE #k;
    SELECT k.kapt_code, 세대 = COALESCE(NULLIF(k.hhld_cnt, 0), k.ho_cnt),
           주소 = CAST(LTRIM(RTRIM(LEFT(k.doro_juso, PATINDEX('%[0-9] %', k.doro_juso + ' ')))) AS NVARCHAR(200))
      INTO #k FROM silver.kapt_complex k
     WHERE k.is_current = 1 AND k.doro_juso LIKE N'%[0-9]%' AND COALESCE(NULLIF(k.hhld_cnt, 0), k.ho_cnt) > 0;
    /* 대장: 도로명주소 괄호 앞 */
    IF OBJECT_ID('tempdb..#b') IS NOT NULL DROP TABLE #b;
    SELECT DISTINCT 주소 = CAST(LTRIM(RTRIM(LEFT(b.new_plat_plc, CHARINDEX(N' (', b.new_plat_plc + N' (') - 1))) AS NVARCHAR(200)), cb.complex_id
      INTO #b FROM silver.bld_title b JOIN gold.complex_bld cb ON cb.mgm_bldrgst_pk = b.mgm_bldrgst_pk
     WHERE b.is_current = 1 AND b.new_plat_plc LIKE N'%[0-9]%';
    CREATE INDEX ix ON #b (주소);
    BEGIN TRAN;
        DELETE FROM gold.kapt_road_link;                          /* 파생 — 이제 뷰는 첫째 길만 */
        SELECT complex_id, kapt_code INTO #t1 FROM gold.v_complex_kapt;
        SELECT k.kapt_code, c.complex_id, k.주소, k.세대, c.hhld_cnt_sum
          INTO #m FROM #k k JOIN #b b ON b.주소 = k.주소
          JOIN gold.complex c ON c.complex_id = b.complex_id AND c.is_active = 1 AND c.merged_into IS NULL AND c.hhld_cnt_sum > 0
         WHERE ABS(c.hhld_cnt_sum - k.세대) <= 0.05 * k.세대
           AND NOT EXISTS (SELECT 1 FROM #t1 t WHERE t.kapt_code = k.kapt_code)
           AND NOT EXISTS (SELECT 1 FROM #t1 t WHERE t.complex_id = c.complex_id);
        INSERT INTO gold.kapt_road_link (kapt_code, complex_id, 주소, kapt_세대, 대장_세대)
        SELECT m.kapt_code, m.complex_id, m.주소, m.세대, m.hhld_cnt_sum FROM #m m
         WHERE 1 = (SELECT COUNT(DISTINCT m2.complex_id) FROM #m m2 WHERE m2.kapt_code = m.kapt_code)
           AND 1 = (SELECT COUNT(DISTINCT m3.kapt_code)  FROM #m m3 WHERE m3.complex_id = m.complex_id)
         GROUP BY m.kapt_code, m.complex_id, m.주소, m.세대, m.hhld_cnt_sum;
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
    SELECT * INTO #v FROM gold.v_complex_kapt;          /* 무거운 계산은 트랜잭션 밖에서 */
    BEGIN TRAN;
        DELETE FROM gold.complex_kapt;
        INSERT INTO gold.complex_kapt SELECT v.*, SYSDATETIME() FROM #v v;
    COMMIT;
    SELECT 연결 = (SELECT COUNT(*) FROM gold.complex_kapt), 초 = DATEDIFF(SECOND, @t, SYSDATETIME());
END
GO
