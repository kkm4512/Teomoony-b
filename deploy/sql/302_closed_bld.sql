/* 302_closed_bld : 폐쇄말소 건축물대장 (2026-10-22)
   출처: 공공데이터포털 15137093 '국토교통부_건축HUB_폐쇄말소대장정보 서비스' (ShtRgstHubService)
     getSrTitleInfo 표제부 · getSrRecapTitleInfo 총괄표제부. 키 = 폐쇄대장 PK(mgmShtregPk) — 현 대장 PK 와 다른 체계.
   사장님 결정(CONTEXT 11-180):
     ① 현재 단지(gold.complex)와 **섞지 않는다** — 따로 표, 화면엔 '철거됨'.
     ② 옛 ↔ 지금 단지는 **이름 말고 PNU** — 같은 필지에 지금 단지가 하나일 때만.
     ③ 대상 = **전부**(단독·근생 포함). ④ 값은 원문 그대로 — 원문 0·빈칸 = '안 적음' → NULL. 말소일·사유 계산·추정 안 함.
   철거 단지(gold.closed_site) 묶는 규칙 — 계산이 아니라 묶기만:
     **같은 대지(PNU) + 같은 말소일** 의 표제부·총괄표제부를 한 묶음. 말소일이 비면 빈 것끼리.
     (폐쇄 표제부에는 상위 총괄 PK 가 없다 — 그래서 대지·말소일로 묶는다. 부속지번은 아직 안 받음.)
*/
SET NOCOUNT ON;
GO
IF OBJECT_ID('silver.bld_closed_title') IS NULL
CREATE TABLE silver.bld_closed_title (
    mgm_shtreg_pk    VARCHAR(30)    NOT NULL CONSTRAINT pk_bld_closed_title PRIMARY KEY,
    shter_gb_cd      VARCHAR(2)     NULL,      -- 폐쇄 구분 코드
    shter_gb_nm      NVARCHAR(20)   NULL,      -- 말소 · 폐쇄 · 일부말소 · 일부폐쇄 (원문)
    shter_day        CHAR(8)        NULL,      -- 말소(폐쇄)일 원문
    regstr_gb_nm     NVARCHAR(20)   NULL,
    regstr_kind_nm   NVARCHAR(20)   NULL,
    sigungu_cd       CHAR(5)        NOT NULL,
    bjdong_cd        CHAR(5)        NOT NULL,
    plat_gb_cd       VARCHAR(1)     NULL,
    bun              VARCHAR(10)    NULL,
    ji               VARCHAR(10)    NULL,
    pnu              CHAR(19)       NULL,
    plat_plc         NVARCHAR(300)  NULL,
    new_plat_plc     NVARCHAR(300)  NULL,
    bld_nm           NVARCHAR(200)  NULL,
    dong_nm          NVARCHAR(100)  NULL,
    main_atch_gb_nm  NVARCHAR(20)   NULL,
    plat_area        DECIMAL(19,5)  NULL,
    arch_area        DECIMAL(19,5)  NULL,
    bc_rat           DECIMAL(9,5)   NULL,
    tot_area         DECIMAL(19,5)  NULL,
    vl_rat           DECIMAL(9,5)   NULL,
    strct_nm         NVARCHAR(100)  NULL,
    main_purps_cd    VARCHAR(10)    NULL,
    main_purps_nm    NVARCHAR(100)  NULL,
    etc_purps        NVARCHAR(400)  NULL,
    hhld_cnt         INT            NULL,
    fmly_cnt         INT            NULL,
    ho_cnt           INT            NULL,
    heit             DECIMAL(13,3)  NULL,
    grnd_flr_cnt     INT            NULL,
    ugrnd_flr_cnt    INT            NULL,
    use_apr_day      CHAR(8)        NULL,
    pms_day          CHAR(8)        NULL,
    stcns_day        CHAR(8)        NULL,
    crtn_day         CHAR(8)        NULL,
    loaded_at        DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME()
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_bld_closed_title_pnu')
    CREATE INDEX ix_bld_closed_title_pnu ON silver.bld_closed_title (pnu, shter_day);
GO
IF OBJECT_ID('silver.bld_closed_recap') IS NULL
CREATE TABLE silver.bld_closed_recap (
    mgm_shtreg_pk    VARCHAR(30)    NOT NULL CONSTRAINT pk_bld_closed_recap PRIMARY KEY,
    shter_gb_cd      VARCHAR(2)     NULL,
    shter_gb_nm      NVARCHAR(20)   NULL,
    shter_day        CHAR(8)        NULL,
    regstr_gb_nm     NVARCHAR(20)   NULL,
    new_old_regstr_gb_nm NVARCHAR(20) NULL,
    sigungu_cd       CHAR(5)        NOT NULL,
    bjdong_cd        CHAR(5)        NOT NULL,
    plat_gb_cd       VARCHAR(1)     NULL,
    bun              VARCHAR(10)    NULL,
    ji               VARCHAR(10)    NULL,
    pnu              CHAR(19)       NULL,
    plat_plc         NVARCHAR(300)  NULL,
    new_plat_plc     NVARCHAR(300)  NULL,
    bld_nm           NVARCHAR(200)  NULL,
    plat_area        DECIMAL(19,5)  NULL,
    arch_area        DECIMAL(19,5)  NULL,
    bc_rat           DECIMAL(9,5)   NULL,
    tot_area         DECIMAL(19,5)  NULL,
    vl_rat           DECIMAL(9,5)   NULL,
    main_purps_nm    NVARCHAR(100)  NULL,
    main_bld_cnt     INT            NULL,
    atch_bld_cnt     INT            NULL,
    hhld_cnt         INT            NULL,
    fmly_cnt         INT            NULL,
    ho_cnt           INT            NULL,
    tot_pkng_cnt     INT            NULL,
    use_apr_day      CHAR(8)        NULL,
    pms_day          CHAR(8)        NULL,
    crtn_day         CHAR(8)        NULL,
    loaded_at        DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME()
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_bld_closed_recap_pnu')
    CREATE INDEX ix_bld_closed_recap_pnu ON silver.bld_closed_recap (pnu, shter_day);
GO
/* 파생표 — 다시 만들 수 있다 */
IF OBJECT_ID('gold.closed_site') IS NULL
CREATE TABLE gold.closed_site (
    site_key         VARCHAR(30)    NOT NULL CONSTRAINT pk_closed_site PRIMARY KEY,  -- pnu + '-' + 말소일(없으면 '0')
    pnu              CHAR(19)       NOT NULL,
    shter_day        CHAR(8)        NULL,
    이름             NVARCHAR(200)  NULL,      -- 총괄표제부 건물명 → 없으면 표제부 건물명(하나뿐일 때) → NULL
    이름출처         NVARCHAR(20)   NULL,
    주용도           NVARCHAR(100)  NULL,      -- 총괄 → 없으면 표제부(하나뿐일 때)
    동수             INT            NOT NULL,  -- 이 묶음의 표제부 줄 수(센 것, 원문 값 아님)
    총괄세대         INT            NULL,      -- 총괄표제부 원문 세대수
    사용승인일       CHAR(8)        NULL,      -- 총괄 → 없으면 표제부(하나뿐일 때)
    폐쇄구분         NVARCHAR(20)   NULL,
    plat_plc         NVARCHAR(300)  NULL,
    new_plat_plc     NVARCHAR(300)  NULL,
    lat              DECIMAL(10,7)  NULL,      -- 그 필지가 지금도 있으면 필지 중심
    lng              DECIMAL(10,7)  NULL,
    now_complex_id   INT            NULL,      -- 같은 PNU 의 지금 단지(후보 1일 때만)
    now_근거         NVARCHAR(100)  NULL
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_closed_site_pnu')
    CREATE INDEX ix_closed_site_pnu ON gold.closed_site (pnu);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_closed_site_now')
    CREATE INDEX ix_closed_site_now ON gold.closed_site (now_complex_id) WHERE now_complex_id IS NOT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_closed_site_ll')
    CREATE INDEX ix_closed_site_ll ON gold.closed_site (lat, lng) WHERE lat IS NOT NULL;
GO
CREATE OR ALTER PROCEDURE gold.usp_build_closed_site
    @sgg CHAR(5) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF OBJECT_ID('tempdb..#cs302') IS NOT NULL DROP TABLE #cs302;
    WITH k AS (
        SELECT pnu, shter_day FROM silver.bld_closed_title WHERE pnu IS NOT NULL AND (@sgg IS NULL OR sigungu_cd = @sgg)
        UNION
        SELECT pnu, shter_day FROM silver.bld_closed_recap WHERE pnu IS NOT NULL AND (@sgg IS NULL OR sigungu_cd = @sgg)
    )
    SELECT site_key = CAST(k.pnu + '-' + ISNULL(k.shter_day, '0') AS VARCHAR(30)), k.pnu, k.shter_day,
           r_nm = r.bld_nm, r_purps = r.main_purps_nm, r_hhld = r.hhld_cnt, r_apr = r.use_apr_day, r_gb = r.shter_gb_nm,
           r_plc = r.plat_plc, r_new = r.new_plat_plc, r_n = r.n,
           t_n = ISNULL(t.n, 0), t_nm = t.nm1, t_nm_n = t.nm_n, t_purps = t.purps1, t_purps_n = t.purps_n,
           t_apr = t.apr1, t_apr_n = t.apr_n, t_gb = t.gb1, t_plc = t.plc1, t_new = t.new1
      INTO #cs302
      FROM k
      OUTER APPLY (SELECT n = COUNT(*), bld_nm = MIN(bld_nm), main_purps_nm = MIN(main_purps_nm), hhld_cnt = MIN(hhld_cnt),
                          use_apr_day = MIN(use_apr_day), shter_gb_nm = MIN(shter_gb_nm), plat_plc = MIN(plat_plc), new_plat_plc = MIN(new_plat_plc)
                     FROM silver.bld_closed_recap x WHERE x.pnu = k.pnu AND ISNULL(x.shter_day, '0') = ISNULL(k.shter_day, '0')) r
      OUTER APPLY (SELECT n = COUNT(*), nm1 = MIN(bld_nm), nm_n = COUNT(DISTINCT bld_nm),
                          purps1 = MIN(main_purps_nm), purps_n = COUNT(DISTINCT main_purps_nm),
                          apr1 = MIN(use_apr_day), apr_n = COUNT(DISTINCT use_apr_day),
                          gb1 = MIN(shter_gb_nm), plc1 = MIN(plat_plc), new1 = MIN(new_plat_plc)
                     FROM silver.bld_closed_title x WHERE x.pnu = k.pnu AND ISNULL(x.shter_day, '0') = ISNULL(k.shter_day, '0')) t;

    BEGIN TRAN;
        DELETE FROM gold.closed_site WHERE @sgg IS NULL OR LEFT(pnu, 5) = @sgg;
        INSERT INTO gold.closed_site (site_key, pnu, shter_day, 이름, 이름출처, 주용도, 동수, 총괄세대, 사용승인일, 폐쇄구분, plat_plc, new_plat_plc)
        SELECT site_key, pnu, shter_day,
               이름 = CASE WHEN r_n = 1 AND r_nm IS NOT NULL THEN r_nm WHEN t_nm_n = 1 THEN t_nm END,
               이름출처 = CASE WHEN r_n = 1 AND r_nm IS NOT NULL THEN N'총괄표제부' WHEN t_nm_n = 1 THEN N'표제부' END,
               주용도 = CASE WHEN r_n = 1 AND r_purps IS NOT NULL THEN r_purps WHEN t_purps_n = 1 THEN t_purps END,
               동수 = t_n,
               총괄세대 = CASE WHEN r_n = 1 THEN r_hhld END,
               사용승인일 = CASE WHEN r_n = 1 AND r_apr IS NOT NULL THEN r_apr WHEN t_apr_n = 1 THEN t_apr END,
               폐쇄구분 = ISNULL(r_gb, t_gb), ISNULL(r_plc, t_plc), ISNULL(r_new, t_new)
          FROM #cs302;
        /* 위치: 그 필지가 지금도 있으면 필지 중심(없으면 비움 — 지어내지 않는다) */
        UPDATE s SET lat = p.centroid_lat, lng = p.centroid_lng
          FROM gold.closed_site s JOIN silver.cadastral_parcel p ON p.pnu = s.pnu AND p.is_current = 1
         WHERE @sgg IS NULL OR LEFT(s.pnu, 5) = @sgg;
        /* 지금 그 자리 단지: 같은 PNU 에 지금 단지가 하나일 때만 */
        UPDATE s SET now_complex_id = c.cid, now_근거 = N'같은 필지(PNU)에 지금 단지 1'
          FROM gold.closed_site s
          CROSS APPLY (SELECT cid = MIN(cp.complex_id), n = COUNT(DISTINCT cp.complex_id)
                         FROM gold.complex_pnu cp JOIN gold.complex x ON x.complex_id = cp.complex_id AND x.merged_into IS NULL
                        WHERE cp.pnu = s.pnu) c
         WHERE c.n = 1 AND (@sgg IS NULL OR LEFT(s.pnu, 5) = @sgg);
    COMMIT;
    SELECT 묶음 = COUNT(*), 이름있음 = SUM(CASE WHEN 이름 IS NOT NULL THEN 1 ELSE 0 END),
           위치있음 = SUM(CASE WHEN lat IS NOT NULL THEN 1 ELSE 0 END), 지금단지 = SUM(CASE WHEN now_complex_id IS NOT NULL THEN 1 ELSE 0 END)
      FROM gold.closed_site WHERE @sgg IS NULL OR LEFT(pnu, 5) = @sgg;
END
GO

/* 2026-10-22 13:07: 성북 1129011200 에서 numeric 넘침(8115) — 원문 건폐율·용적률에 큰 값이 온다(대장에 소수점이 빠진 듯한 값, 11-? 정릉동 59,315% 와 같은 종류).
   원문 그대로 담도록 칸을 넓힌다(값을 고치거나 버리지 않는다). */
ALTER TABLE silver.bld_closed_title ALTER COLUMN bc_rat DECIMAL(19,5) NULL;
ALTER TABLE silver.bld_closed_title ALTER COLUMN vl_rat DECIMAL(19,5) NULL;
ALTER TABLE silver.bld_closed_title ALTER COLUMN heit   DECIMAL(19,3) NULL;
ALTER TABLE silver.bld_closed_recap ALTER COLUMN bc_rat DECIMAL(19,5) NULL;
ALTER TABLE silver.bld_closed_recap ALTER COLUMN vl_rat DECIMAL(19,5) NULL;
GO
