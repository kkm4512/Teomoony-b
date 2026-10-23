/* 2026-10-23 23:03 사장님 "학교이름, 학생수, 교사학생수" — 학교알리미 OpenAPI(한국교육학술정보원 · 출처 표시 조건 자유 이용)
   ① silver.schoolinfo       학교기본정보(apiType 0): 정보공시 학교코드(SCHUL_CODE · 'S…') · 이름 · 학교급 · 법정동코드 · 설립일 · 좌표 · 폐교
   ② silver.schoolinfo_stat  학년별·학급별 학생수(apiType 09): 학급수 · 학생수 · 학급당 학생수 · 교사수 · 수업교원 1인당 학생수 — **공시값 그대로**(계산 안 함)
   ★ 학교알리미 코드는 우리 학교 위치(교육부 학교ID 'B…')와 **다른 체계**다. 잇는 것은 gold.school_link(335)에서만. */
IF OBJECT_ID('silver.schoolinfo') IS NULL
CREATE TABLE silver.schoolinfo (
    schul_code      VARCHAR(12)    NOT NULL PRIMARY KEY,
    schul_nm        NVARCHAR(100)  NULL,
    knd_code        CHAR(2)        NULL,          -- 02 초 03 중 04 고 05 특수 06 그외 07 각종
    fond_sc         NVARCHAR(10)   NULL,          -- 국립 · 공립 · 사립
    fond_ymd        CHAR(8)        NULL,
    adrcd_cd        CHAR(10)       NULL,          -- 법정동코드(원문 ADRCD_CD)
    road_addr       NVARCHAR(200)  NULL,
    addr_brkdn      NVARCHAR(200)  NULL,
    dtlad_brkdn     NVARCHAR(200)  NULL,
    lat             DECIMAL(10,7)  NULL,
    lng             DECIMAL(10,7)  NULL,
    close_yn        CHAR(1)        NULL,
    bnhh_yn         CHAR(1)        NULL,          -- 분교
    coedu           NVARCHAR(10)   NULL,
    hmpg            NVARCHAR(200)  NULL,
    raw_json        NVARCHAR(MAX)  NULL,
    collected_at    DATE           NOT NULL
);
GO
IF OBJECT_ID('silver.schoolinfo_stat') IS NULL
CREATE TABLE silver.schoolinfo_stat (
    schul_code      VARCHAR(12)    NOT NULL,
    pban_yr         SMALLINT       NOT NULL,      -- 공시연도
    class_cnt       INT            NULL,          -- COL_C_SUM 학급수(계)
    stdnt_cnt       INT            NULL,          -- COL_S_SUM 학생수(계)
    per_class       DECIMAL(6,1)   NULL,          -- COL_SUM 학급당 학생수(계)
    teach_cnt       INT            NULL,          -- TEACH_CNT 교사수
    per_teacher     DECIMAL(6,1)   NULL,          -- TEACH_CAL 수업교원 1인당 학생수
    excp_yn         CHAR(1)        NULL,          -- PBAN_EXCP_YN 공시 제외
    excp_rsn        NVARCHAR(200)  NULL,
    raw_json        NVARCHAR(MAX)  NULL,
    collected_at    DATE           NOT NULL,
    CONSTRAINT pk_schoolinfo_stat PRIMARY KEY (schul_code, pban_yr)
);
GO
SELECT j = (SELECT 기본 = (SELECT COUNT(*) FROM silver.schoolinfo), 통계 = (SELECT COUNT(*) FROM silver.schoolinfo_stat) FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
