/* 178. 학교 (초·중·고) — 위치 (2026-10-19)
   출처: 전국초중등학교위치표준데이터 (data.go.kr 15021148)
         제공 한국교육시설안전원 / 소관 교육부 · 근거 초중등교육법
         요청주소 https://api.data.go.kr/openapi/tn_pubr_public_elesch_mskul_lc_api
         활용승인 자동 · 개발계정 10,000건/일 · numOfRows 최대 1000

   ★ 왜 상권 데이터로 못 하나
     소상공인 상가(상권)정보에는 **학교가 0건**이다(2026-10-19 실측:
     소분류/중분류 어디에도 '학교·초등·중학·고등·유치원·어린이집' 이 없다).
     학교는 상가가 아니라서 애초에 수집 대상이 아니다. 그래서 별도 출처를 쓴다.

   ★ 코드로 붙지 않는다 — 좌표만 온다
     이 표준데이터에는 PNU 도 건물관리번호도 없다. 지번주소(lnmadr)는 오지만
     문자열이라 그대로 PNU 가 되지 않는다. **지금은 좌표 거리만 쓴다.**
     지번을 PNU 로 바꾸는 건 별도 작업이고, 틀리면 조용히 틀리므로 하지 않는다.
     (정책 1장: 조용히 틀린 PNU 는 NULL 보다 나쁘다)

   ★ 거리는 geography — 미터로 재야 한다. semas_store 와 같은 이유다.

   ★ 운영상태를 반드시 본다
     '폐교' 가 섞여 온다. 화면에서는 oper_sttus = N'운영' 만 센다.
     여기서 지우지는 않는다 — 원본을 줄이면 나중에 왜 없는지 알 수 없다.
*/
IF OBJECT_ID('silver.school') IS NULL
CREATE TABLE silver.school (
    school_sk     BIGINT IDENTITY(1,1) NOT NULL,
    school_id     VARCHAR(20)    NOT NULL,   -- 학교ID (자연키)
    school_nm     NVARCHAR(200)  NULL,
    school_se     NVARCHAR(20)   NULL,       -- 초등학교 / 중학교 / 고등학교
    fond_date     NVARCHAR(20)   NULL,       -- 설립일자 (YYYY-MM-DD 로 온다)
    fond_type     NVARCHAR(20)   NULL,       -- 공립 / 사립
    bnhh_se       NVARCHAR(20)   NULL,       -- 본교 / 분교
    oper_sttus    NVARCHAR(20)   NULL,       -- 운영 / 폐교 ...
    lnmadr        NVARCHAR(300)  NULL,       -- 소재지지번주소
    rdnmadr       NVARCHAR(300)  NULL,       -- 소재지도로명주소
    cddc_code     VARCHAR(20)    NULL,       -- 시도교육청코드
    cddc_nm       NVARCHAR(60)   NULL,
    edc_sport     VARCHAR(20)    NULL,       -- 교육지원청코드
    edc_sport_nm  NVARCHAR(60)   NULL,
    lat           DECIMAL(11,8)  NULL,
    lon           DECIMAL(12,8)  NULL,
    geog          geography      NULL,       -- SRID 4326
    reference_date NVARCHAR(20)  NULL,       -- 데이터기준일자
    collected_at  CHAR(8)        NULL,
    row_hash      BINARY(32)     NOT NULL,
    valid_from    DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    valid_to      DATETIME2(0)   NOT NULL DEFAULT '9999-12-31',
    is_current    BIT            NOT NULL DEFAULT 1,
    CONSTRAINT pk_school PRIMARY KEY CLUSTERED (school_sk)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='uq_school_current')
CREATE UNIQUE INDEX uq_school_current ON silver.school (school_id) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_school_se')
CREATE INDEX ix_school_se ON silver.school (school_se) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='sx_school_geog')
CREATE SPATIAL INDEX sx_school_geog ON silver.school (geog);
GO
PRINT '178 완료 - silver.school';
