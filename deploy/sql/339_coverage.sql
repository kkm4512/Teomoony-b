/* 2026-10-24 11:37 사장님 "전국구로 넓혀 가자 · ㄱㄱ" — 1단계: '어디까지 받았나' 를 **한 표**로.
   meta.coverage = 자료 × 시군구(5자리) → 실제로 들어 있는 행 수 · 최근 값. **적재 기록이 아니라 데이터에서 센다**(받았다고 적고 비어 있으면 거짓말이다).
   ★ 시군구 칸이 있는 자료는 그 칸으로 · 없는 점 자료(학원 · 병원 · 약국 · 학교 · 버스 · 지하철)는 좌표가 든 **법정동 경계**(silver.lawd_boundary)로 가른다.
     경계가 없는 지역의 점은 '시군구 모름' 으로 센다 — 전국으로 넓힐 때 법정동 경계를 먼저 받는다.
   ★ 화면의 '아직 안 받음(SCOPE)' 판단과 적재 대상 목록이 이 표 하나를 본다. 무거운 표가 있어 백그라운드(잡)로 갱신한다. */
IF SCHEMA_ID('meta') IS NULL EXEC('CREATE SCHEMA meta');
GO
IF OBJECT_ID('meta.coverage') IS NULL
CREATE TABLE meta.coverage (
    자료       NVARCHAR(30)  NOT NULL,
    sgg_cd     CHAR(5)       NOT NULL,      -- '00000' = 시군구 모름(경계 밖 점)
    행수       BIGINT        NOT NULL,
    최근       NVARCHAR(20)  NULL,          -- 그 자료의 최근 날짜 · 연월 · 공시차수(있을 때)
    센때       DATETIME2(0)  NOT NULL,
    CONSTRAINT pk_meta_coverage PRIMARY KEY (자료, sgg_cd)
);
GO
/* 적재 **대상** 시군구 — 하나의 설정(meta.load_target)에서. 적재 스크립트 · 내보내기 목록이 지역을 코드에 적지 않고 이걸 본다.
   (받은 것 = meta.coverage · 받을 것 = 이 뷰. 둘은 다르다 — 받을 것인데 아직 안 받은 곳이 '진행 중'이다) */
CREATE OR ALTER VIEW meta.v_target_sgg AS
SELECT sgg_cd = CAST(sgg_cd AS CHAR(5)), 시 = CAST(LEFT(sgg_cd, 4) + '0' AS CHAR(5))
  FROM meta.load_target WHERE enabled = 1 AND sgg_cd IS NOT NULL GROUP BY sgg_cd;
GO
CREATE OR ALTER PROCEDURE meta.usp_refresh_coverage
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    IF OBJECT_ID('tempdb..#c') IS NOT NULL DROP TABLE #c;
    CREATE TABLE #c (자료 NVARCHAR(30), sgg_cd CHAR(5), 행수 BIGINT, 최근 NVARCHAR(20));

    /* 시군구 칸이 있는 자료 */
    INSERT #c SELECT N'단지', sigungu_cd, COUNT(*), MAX(oldest_use_apr) FROM gold.complex WHERE is_active = 1 AND sigungu_cd IS NOT NULL GROUP BY sigungu_cd;
    INSERT #c SELECT N'실거래', sgg_cd, COUNT_BIG(*), MAX(deal_ymd) FROM silver.rtms_trade WHERE sgg_cd IS NOT NULL GROUP BY sgg_cd;
    INSERT #c SELECT N'건축물대장', sigungu_cd, COUNT(*), MAX(crtn_day) FROM silver.bld_title WHERE is_current = 1 GROUP BY sigungu_cd;
    INSERT #c SELECT N'총괄표제부', sigungu_cd, COUNT(*), MAX(crtn_day) FROM silver.bld_recap_title WHERE is_current = 1 GROUP BY sigungu_cd;
    INSERT #c SELECT N'건물외곽선', LEFT(lawd_cd, 5), COUNT_BIG(*), NULL FROM silver.building_footprint WHERE is_current = 1 AND lawd_cd IS NOT NULL GROUP BY LEFT(lawd_cd, 5);
    INSERT #c SELECT N'전유부', sigungu_cd, COUNT(*), MAX(crtn_day) FROM silver.bld_expos WHERE is_current = 1 GROUP BY sigungu_cd;
    INSERT #c SELECT N'주택공시가격', sigungu_cd, COUNT_BIG(*), MAX(std_day) FROM silver.bld_hsprc WHERE is_current = 1 GROUP BY sigungu_cd;
    INSERT #c SELECT N'공동주택가격', LEFT(pnu, 5), COUNT_BIG(*), MAX(CONCAT(기준연도, '')) FROM silver.ned_aphus_price WHERE pnu IS NOT NULL GROUP BY LEFT(pnu, 5);
    INSERT #c SELECT N'건축인허가', sigungu_cd, COUNT(*), MAX(arch_pms_day) FROM silver.arch_permit WHERE is_current = 1 GROUP BY sigungu_cd;
    INSERT #c SELECT N'폐쇄대장', sigungu_cd, COUNT(*), MAX(shter_day) FROM silver.bld_closed_title GROUP BY sigungu_cd;
    INSERT #c SELECT N'필지', LEFT(pnu, 5), COUNT(*), NULL FROM silver.cadastral_parcel WHERE is_current = 1 GROUP BY LEFT(pnu, 5);
    INSERT #c SELECT N'토지특성', LEFT(pnu, 5), COUNT_BIG(*), MAX(CONCAT(base_year, '')) FROM silver.land_char WHERE is_current = 1 GROUP BY LEFT(pnu, 5);
    INSERT #c SELECT N'토지이동', LEFT(pnu, 5), COUNT_BIG(*), MAX(CONVERT(CHAR(10), 받은시각, 23)) FROM silver.land_move_hist GROUP BY LEFT(pnu, 5);
    INSERT #c SELECT N'토지이용계획', LEFT(pnu, 5), COUNT_BIG(*), NULL FROM silver.land_use_plan WHERE is_current = 1 GROUP BY LEFT(pnu, 5);
    INSERT #c SELECT N'K-apt', LEFT(bjd_code, 5), COUNT(*), NULL FROM silver.kapt_complex WHERE is_current = 1 AND bjd_code IS NOT NULL GROUP BY LEFT(bjd_code, 5);
    INSERT #c SELECT N'관리비', LEFT(k.bjd_code, 5), COUNT_BIG(*), MAX(c.ym) FROM silver.kapt_cost c JOIN silver.kapt_complex k ON k.kapt_code = c.kapt_code AND k.is_current = 1 GROUP BY LEFT(k.bjd_code, 5);
    INSERT #c SELECT N'청약공고', LEFT(lawd_cd, 5), COUNT(*), MAX(rcrit_pblanc_de) FROM silver.applyhome_pblanc WHERE lawd_cd IS NOT NULL GROUP BY LEFT(lawd_cd, 5);
    INSERT #c SELECT N'상가', signgu_cd, COUNT(*), MAX(CONVERT(CHAR(10), collected_at, 23)) FROM silver.semas_store WHERE is_current = 1 AND signgu_cd IS NOT NULL GROUP BY signgu_cd;
    INSERT #c SELECT N'어린이집', arcode, COUNT(*), MAX(CONVERT(CHAR(10), 기준일, 23)) FROM silver.childcare WHERE is_current = 1 GROUP BY arcode;
    INSERT #c SELECT N'유치원', sgg_cd, COUNT(*), MAX(pbnt_tmng) FROM silver.kindergarten WHERE sgg_cd IS NOT NULL GROUP BY sgg_cd;
    INSERT #c SELECT N'유치원공시', k.sgg_cd, COUNT(*), MAX(i.pbnt_tmng) FROM silver.kinder_info i JOIN silver.kindergarten k ON k.kinder_cd = i.kinder_cd GROUP BY k.sgg_cd;
    INSERT #c SELECT N'학교알리미', LEFT(i.adrcd_cd, 5), COUNT(DISTINCT i.schul_code), MAX(CONCAT(t.pban_yr, '')) FROM silver.schoolinfo i LEFT JOIN silver.schoolinfo_stat t ON t.schul_code = i.schul_code GROUP BY LEFT(i.adrcd_cd, 5);
    INSERT #c SELECT N'정비구역', signgu_se, COUNT(*), NULL FROM silver.redev_zone WHERE is_current = 1 AND signgu_se IS NOT NULL GROUP BY signgu_se;
    INSERT #c SELECT N'통학구역', CONCAT(sd_cd, sgg_cd), COUNT(*), MAX(base_dt) FROM silver.school_zone WHERE sgg_cd IS NOT NULL GROUP BY CONCAT(sd_cd, sgg_cd);  -- sgg_cd 는 3자리(시도 sd_cd 와 붙여 5자리)
    INSERT #c SELECT N'법정동경계', LEFT(lawd_cd, 5), COUNT(*), NULL FROM silver.lawd_boundary WHERE is_current = 1 GROUP BY LEFT(lawd_cd, 5);

    /* 점 자료 — 좌표가 든 법정동 경계의 시군구(경계가 없으면 '00000') */
    IF OBJECT_ID('tempdb..#pt') IS NOT NULL DROP TABLE #pt;
    CREATE TABLE #pt (자료 NVARCHAR(30), lat FLOAT, lon FLOAT);
    INSERT #pt SELECT N'학원', lat, lon FROM silver.academy WHERE is_current = 1 AND lat IS NOT NULL;
    INSERT #pt SELECT N'병원', lat, lng FROM silver.hira_inst WHERE is_current = 1 AND lat IS NOT NULL;
    INSERT #pt SELECT N'약국인허가', lat, lng FROM silver.mois_pharmacy WHERE lat IS NOT NULL;
    INSERT #pt SELECT N'학교', lat, lon FROM silver.school WHERE is_current = 1 AND lat IS NOT NULL;
    INSERT #pt SELECT N'버스정류장', lat, lon FROM silver.bus_stop WHERE is_current = 1 AND lat IS NOT NULL;
    INSERT #pt SELECT N'지하철역', lat, lon FROM silver.subway_station WHERE is_current = 1 AND lat IS NOT NULL;
    INSERT #c
    SELECT p.자료, ISNULL(LEFT(b.lawd_cd, 5), '00000'), COUNT_BIG(*), NULL
      FROM #pt p
      OUTER APPLY (SELECT TOP 1 lb.lawd_cd FROM silver.lawd_boundary lb
                    WHERE lb.is_current = 1 AND p.lon BETWEEN lb.bbox_minx AND lb.bbox_maxx AND p.lat BETWEEN lb.bbox_miny AND lb.bbox_maxy
                      AND lb.geom.STIntersects(geometry::Point(p.lon, p.lat, lb.geom.STSrid)) = 1) b
     GROUP BY p.자료, ISNULL(LEFT(b.lawd_cd, 5), '00000');

    BEGIN TRAN;
      DELETE FROM meta.coverage;
      INSERT meta.coverage (자료, sgg_cd, 행수, 최근, 센때)
      SELECT 자료, sgg_cd, SUM(행수), MAX(최근), SYSDATETIME() FROM #c WHERE sgg_cd IS NOT NULL AND LEN(sgg_cd) = 5 GROUP BY 자료, sgg_cd;
    COMMIT;
    SELECT 자료 = COUNT(DISTINCT 자료), 줄 = COUNT(*), 시군구 = COUNT(DISTINCT sgg_cd) FROM meta.coverage;
END
GO
