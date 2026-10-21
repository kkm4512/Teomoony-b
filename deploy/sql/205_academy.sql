/* 205. 학원·교습소 (2026-10-20)
   출처: 교육부 · 16개 시도교육청 — 나이스 교육정보 개방포털 "학원교습소정보"
         요청주소 https://open.neis.go.kr/hub/acaInsTiInfo
         이용허락범위 제한없음 · 호출 제한 없음 · 적재주기 매주
         근거 학원의 설립·운영 및 과외교습에 관한 법률

   ★ 왜 상권 데이터를 두고 또 받나
     화면의 '학원' 칸은 지금까지 소상공인 상가(상권)정보였다. 그건
     **사업자 등록**이라 업종 분류(입시·교과학원 / 외국어학원 …)밖에 없다.
     이쪽은 **교육청 등록 원본**이라 분야·교습계열·교습과정·정원·등록상태·
     수강료가 그대로 온다. 애 학원 찾는 사람이 보고 싶은 건 업종이 아니라
     '여기서 수학을 가르치나' 다. 그래서 바꾼다.
     ★ 두 수를 나란히 두지 않는다 — 같은 이름으로 다른 수를 말하면 안 된다.

   ★ 좌표가 안 온다 (2026-10-20 명세를 눈으로 확인함)
     출력 25개 항목에 위도·경도도, PNU 도, 건물관리번호도 없다. 도로명주소
     문자열과 우편번호뿐이다. 그래서 lat/lon 은 **적재 때 NULL 로 둔다.**
     geocode_academy.py 가 VWorld 지오코더로 나중에 채우고, 채우지 못한 것은
     NULL 로 남기고 geocode_status 에 이유를 적는다.
     (정책 1장: 조용히 틀린 좌표는 NULL 보다 나쁘다)
     silver.road_addr(도로명주소↔PNU)이 비어 있어서 코드로 붙일 길이 아직 없다.
     그 표가 차면 지오코딩 없이 PNU 로 붙일 수 있다 — 그때 다시 본다.

   ★ 학원지정번호는 시도교육청 안에서만 고유하다
     버스 ARS 번호가 시·도 안에서만 고유했던 것과 **같은 함정**이다. 전국으로
     넓히면 번호가 겹친다. 그래서 자연키에 시도교육청코드를 반드시 넣는다.

   ★ 한 학원이 여러 줄로 오나 싶어 자연키에 분야·계열·과정까지 넣었다.
     그 뒤 서울 25,512건을 다 받아 세어 봤다(2026-10-20):
       자연키 겹침 0 · 학원지정번호 25,512개 = 행 수  ->  **1줄 = 1학원**
     자연키가 과하게 자세하지만 그대로 둔다 — 다른 교육청이 다를 수 있고,
     겹치면 적재기가 소리를 낸다.

   ★ 등록상태 — 실측은 **전부 '개원'** 이었다 (25,512/25,512).
     폐원·휴원은 이 API 로 오지 않는다. 그래도 화면은 개원만 세는 필터를
     **남긴다** — 나중에 섞여 오면 조용히 들어오면 안 되니까.
     휴원종료일자는 '99991231' 이 정상값이다.

   ★ 도로명주소는 실측 결과 **한 건도 비지 않았다**(0건).
     서로 다른 주소는 12,366개 — 지오코더는 그만큼만 부르면 된다
     (한 건물에 평균 2곳이 들어 있다).

   ★ 전화번호가 마스킹돼 오는 경우가 있다 ('02-0000-0000' 을 실제로 받았다).
     그대로 담고, 화면에서는 0 만 있는 번호를 안 보여준다.
*/
IF OBJECT_ID('silver.academy') IS NULL
CREATE TABLE silver.academy (
    academy_sk      BIGINT IDENTITY(1,1) NOT NULL,
    nat_key         BINARY(32)     NOT NULL,   -- sha256(시도교육청+지정번호+분야+계열+과정)
    /* 소속 */
    office_cd       CHAR(3)        NOT NULL,   -- 시도교육청코드 (서울 B10)
    office_nm       NVARCHAR(40)   NULL,
    admst_zone_nm   NVARCHAR(40)   NULL,       -- 행정구역명 — ★ 코드가 아니라 '강남구' 같은 이름
    /* 대상 */
    insti_sc_nm     NVARCHAR(20)   NULL,       -- 학원 / 교습소
    aca_asnum       VARCHAR(20)    NOT NULL,   -- 학원지정번호 (시도교육청 안에서만 고유)
    aca_nm          NVARCHAR(200)  NULL,
    estbl_ymd       CHAR(8)        NULL,       -- 개설일자
    reg_ymd         CHAR(8)        NULL,       -- 등록일자
    reg_sttus_nm    NVARCHAR(20)   NULL,       -- 개원 / 휴원 / 폐원
    caa_begin_ymd   CHAR(8)        NULL,       -- 휴원시작일자
    caa_end_ymd     CHAR(8)        NULL,       -- 휴원종료일자 ('99991231' 이 정상값으로 온다)
    /* 규모 */
    tofor_smtot     INT            NULL,       -- 정원합계
    dtm_nmpr_smtot  INT            NULL,       -- 일시수용능력인원합계
    /* 무엇을 가르치나 — 이게 상권 데이터에는 없는 부분이다 */
    realm_sc_nm     NVARCHAR(60)   NULL,       -- 분야명 (입시.검정 및 보습 …)
    le_ord_nm       NVARCHAR(60)   NULL,       -- 교습계열명 (보통교과 …)
    le_crse_list_nm NVARCHAR(400)  NULL,       -- 교습과정목록명 (문법 영어 …)
    le_crse_nm      NVARCHAR(100)  NULL,       -- 교습과정명 (보습 …)
    thcc_cntnt      NVARCHAR(2000) NULL,       -- 인당수강료 '과정:금액, 과정:금액' 문자열
    thcc_othbc_yn   VARCHAR(1)     NULL,       -- 수강료공개여부
    brhs_aca_yn     VARCHAR(1)     NULL,       -- 기숙사학원여부
    /* 어디에 있나 — 주소만 온다 */
    road_addr       NVARCHAR(300)  NULL,       -- 도로명주소
    road_addr_dtl   NVARCHAR(400)  NULL,       -- 도로명상세주소
    /* ★ 2026-10-20: CHAR(5) 였다가 **적재가 터졌다**(2628 truncation, 값 '135519').
       NEIS 를 전수로 재 보니 서울+경기 64,769건 중 **6자리가 11,556건**이다
       — 2015년 이전 **구 우편번호**가 그대로 남아 있다. 5자리 53,205 · 빈값 8.
       원본을 자르지 않는다. 넉넉히 VARCHAR(10) 으로 둔다.
       (나머지 고정길이 칸은 전수로 재서 전부 한도 안인 것을 확인했다.) */
    zip_no          VARCHAR(10)    NULL,
    tel_no          NVARCHAR(40)   NULL,
    load_dtm        CHAR(8)        NULL,       -- 수정일자(개방포털 연계일)
    /* 좌표 — 적재 때는 비어 있다. geocode_academy.py 가 채운다 */
    lat             DECIMAL(11,8)  NULL,
    lon             DECIMAL(12,8)  NULL,
    geog            geography      NULL,       -- SRID 4326
    geocode_status  VARCHAR(20)    NULL,       -- NULL=아직 / OK / NOT_FOUND / FAIL
    geocode_at      DATETIME2(0)   NULL,
    geocode_text    NVARCHAR(300)  NULL,       -- 지오코더가 되돌려준 정제 주소 (검산용)
    /* 운영 */
    collected_at    CHAR(8)        NULL,
    row_hash        BINARY(32)     NOT NULL,
    valid_from      DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    valid_to        DATETIME2(0)   NOT NULL DEFAULT '9999-12-31',
    is_current      BIT            NOT NULL DEFAULT 1,
    CONSTRAINT pk_academy PRIMARY KEY CLUSTERED (academy_sk)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='uq_academy_current')
CREATE UNIQUE INDEX uq_academy_current ON silver.academy (nat_key) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_academy_zone')
CREATE INDEX ix_academy_zone ON silver.academy (office_cd, admst_zone_nm)
  INCLUDE (aca_nm, realm_sc_nm, geocode_status) WHERE is_current = 1;
GO
/* ★ 지오코딩을 이어받으려면 '아직 안 한 것' 을 빨리 찾아야 한다 */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_academy_togeocode')
CREATE INDEX ix_academy_togeocode ON silver.academy (geocode_status)
  INCLUDE (road_addr) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='sx_academy_geog')
CREATE SPATIAL INDEX sx_academy_geog ON silver.academy (geog);
GO
PRINT '205 완료 - silver.academy';
