/* 182. 버스정류장 · 지하철역 (2026-10-19)
   ※ 180(silver.bus_stop)을 **버린다.** 180 은 TAGO API 응답에 맞춰 짰는데
      그 API 에 **서울이 없다**(도시 138곳에 미포함, 실측). 우리 단지는
      81,143개 전부 서울(11)이라 API 로는 한 건도 못 붙인다.
      같은 국토부가 내놓는 **파일데이터에는 서울이 있다**(16,980 승강장).
      → 파일로 간다. 테이블도 파일 컬럼에 맞춘다.

   ── 버스 ──────────────────────────────────────────────
   출처: 국토교통부_전국 버스정류장 위치정보 (data.go.kr 15067528)
         CSV / EUC-KR / 227,065행 / 연 1회 / 파일데이터는 로그인 없이 받는다
   컬럼: 정류장번호, 정류장명, 위도, 경도, 정보수집일, 모바일단축번호,
         도시코드, 도시명, 관리도시명

   ★ 진짜 식별자는 ARS(모바일단축번호) 다
     서울 16,980행 중 838건이 **같은 ARS 에 서울BIS/경기BIS 두 줄**이다
     (예: 24385 가락시장.가락시장역 -> GGB123000294 + SEB123000294).
     그대로 세면 정류장이 부풀어 보인다. **원본은 다 넣고, 셀 때 ARS 로 묶는다.**
     원본을 줄이지 않는 이유는 늘 같다 - 줄이면 왜 없는지 알 수 없다.
   ★ 정류장번호는 전국에서 유일하다(227,065행 중 중복 0, 실측). 자연키로 쓴다.
   ★ 좌표 없음 5건. 넣되 geog 는 NULL 로 둔다.

   ── 지하철 ────────────────────────────────────────────
   출처: 전국도시철도역사정보표준데이터 (data.go.kr 15013205, 국가철도공단)
         XLSX / 1,099행 / 47노선 / 연 1회 / 레일포털에서 받는다
         **이용허락범위 제한 없음**
   컬럼: 역번호, 역사명, 노선번호, 노선명, 영문/한자역사명, 환승역구분,
         환승노선번호, 환승노선명, 역위도, 역경도, 운영기관명,
         역사도로명주소, 역사전화번호, 데이터기준일자

   ★ (노선번호, 역번호) 는 유일하지 않다 — 실측 5건
     · 0736 7호선 '이수' 와 '총신대입구(이수)'  → 같은 역, 이름이 둘
     · 1019/1201/1202 경의중앙선과 경춘선이 **노선번호가 둘 다 I4108**
     · 1809 주안역 경인선이 **완전히 같은 줄 2개**
     그래서 자연키를 (노선번호, 역번호, 노선명, 역사명) 으로 두고,
     완전중복은 적재기가 **지우고 몇 건 뺐는지 말한다.**
   ★ 한 역이 여러 노선이면 **줄이 여러 개**다 (공덕 = 공항철도/5호선/6호선).
     화면에서는 역사명으로 묶어 '노선 여러 개' 로 보여준다.
*/
IF OBJECT_ID('silver.bus_stop') IS NOT NULL DROP TABLE silver.bus_stop;
GO
CREATE TABLE silver.bus_stop (
    stop_sk       BIGINT IDENTITY(1,1) NOT NULL,
    stop_no       VARCHAR(40)    NOT NULL,   -- 정류장번호 (전국 유일, 자연키)
    stop_nm       NVARCHAR(200)  NULL,
    ars_no        VARCHAR(20)    NULL,       -- ★ 모바일단축번호. 같은 승강장을 묶는 키
    city_code     VARCHAR(10)    NULL,
    city_nm       NVARCHAR(60)   NULL,
    mng_city_nm   NVARCHAR(60)   NULL,       -- 관리도시명 (서울BIS / 경기BIS ...)
    lat           DECIMAL(11,8)  NULL,
    lon           DECIMAL(12,8)  NULL,
    geog          geography      NULL,
    collect_date  CHAR(10)       NULL,       -- 정보수집일 (원본 YYYY-MM-DD)
    collected_at  CHAR(8)        NULL,
    row_hash      BINARY(32)     NOT NULL,
    valid_from    DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    valid_to      DATETIME2(0)   NOT NULL DEFAULT '9999-12-31',
    is_current    BIT            NOT NULL DEFAULT 1,
    CONSTRAINT pk_bus_stop PRIMARY KEY CLUSTERED (stop_sk)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='uq_bus_stop_current')
CREATE UNIQUE INDEX uq_bus_stop_current ON silver.bus_stop (stop_no) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_bus_stop_ars')
CREATE INDEX ix_bus_stop_ars ON silver.bus_stop (city_code, ars_no) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='sx_bus_stop_geog')
CREATE SPATIAL INDEX sx_bus_stop_geog ON silver.bus_stop (geog);
GO

IF OBJECT_ID('silver.subway_station') IS NULL
CREATE TABLE silver.subway_station (
    sttn_sk       BIGINT IDENTITY(1,1) NOT NULL,
    line_cd       VARCHAR(20)    NOT NULL,   -- 노선번호
    sttn_cd       VARCHAR(20)    NOT NULL,   -- 역번호
    line_nm       NVARCHAR(100)  NOT NULL,   -- 노선명 (노선번호가 겹쳐서 키에 넣는다)
    sttn_nm       NVARCHAR(120)  NOT NULL,   -- 역사명 (이름이 둘인 역이 있어 키에 넣는다)
    sttn_nm_en    NVARCHAR(200)  NULL,
    sttn_nm_cn    NVARCHAR(120)  NULL,
    transfer_se   NVARCHAR(40)   NULL,       -- 일반역 / 환승역 / 도시철도 환승역 ...
    transfer_line_cd NVARCHAR(200) NULL,
    transfer_line_nm NVARCHAR(400) NULL,
    lat           DECIMAL(11,8)  NULL,
    lon           DECIMAL(12,8)  NULL,
    geog          geography      NULL,
    oper_nm       NVARCHAR(120)  NULL,
    road_addr     NVARCHAR(300)  NULL,
    tel           NVARCHAR(60)   NULL,
    base_date     CHAR(10)       NULL,
    collected_at  CHAR(8)        NULL,
    row_hash      BINARY(32)     NOT NULL,
    valid_from    DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    valid_to      DATETIME2(0)   NOT NULL DEFAULT '9999-12-31',
    is_current    BIT            NOT NULL DEFAULT 1,
    CONSTRAINT pk_subway_station PRIMARY KEY CLUSTERED (sttn_sk)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='uq_subway_current')
CREATE UNIQUE INDEX uq_subway_current ON silver.subway_station
    (line_cd, sttn_cd, line_nm, sttn_nm) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='sx_subway_geog')
CREATE SPATIAL INDEX sx_subway_geog ON silver.subway_station (geog);
GO
PRINT '182 완료 - silver.bus_stop (재정의) / silver.subway_station';
