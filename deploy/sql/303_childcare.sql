/* 303_childcare : 어린이집 (2026-10-22, 사장님 "어린이집 운영 승인 됐엉")
   출처: 보육정보공개 API(api.childcare.go.kr, 한국사회보장정보원) cpmsapi030 '어린이집별 기본정보 조회' — arcode(시군구) 단위.
   키 = .env CHILDCARE_KEY. 적재 etl/load_childcare.py. 이용허락: 출처 표시 · 비영리.
   ★ 이 자료의 0 은 '없음' 이다(놀이터 0 · 반 0) — 빈칸만 NULL. (서울플랜+ 의 '0 = 안 적음' 과 다르다)
   ★ 인원은 원문 기준일(datastdrdt) 값 — 화면에 기준일을 같이 적는다.
   ★ 안양은 arcode 41170(시) 로 받는다 — 41171+41173 = 260 인데 41170 = 324(구 미지정 포함).
*/
SET NOCOUNT ON;
GO
IF OBJECT_ID('silver.childcare') IS NULL
CREATE TABLE silver.childcare (
    stcode           VARCHAR(20)    NOT NULL CONSTRAINT pk_childcare PRIMARY KEY,   -- 어린이집 코드
    arcode           CHAR(5)        NOT NULL,     -- 받은 시군구(요청 키)
    시도             NVARCHAR(20)   NULL,
    시군구           NVARCHAR(20)   NULL,
    이름             NVARCHAR(200)  NOT NULL,
    유형             NVARCHAR(20)   NULL,         -- 국공립 · 민간 · 가정 · 직장 · 법인·단체등 · 협동 · 사회복지법인
    상태             NVARCHAR(10)   NULL,         -- 정상 · 휴지 · 재개 (원문)
    주소             NVARCHAR(300)  NULL,
    전화             VARCHAR(40)    NULL,
    홈페이지         NVARCHAR(300)  NULL,
    정원             INT            NULL,
    현원             INT            NULL,
    보육실수         INT            NULL,
    보육실면적       INT            NULL,
    놀이터수         INT            NULL,
    CCTV수           INT            NULL,
    교직원수         INT            NULL,
    반수             INT            NULL,
    통학차량         NVARCHAR(10)   NULL,         -- 운영 · 미운영 (원문)
    제공서비스       NVARCHAR(200)  NULL,         -- crspec (원문, 예: 일반 · 장애아통합 · 연장보육)
    인가일           CHAR(10)       NULL,
    휴지시작         CHAR(10)       NULL,
    휴지끝           CHAR(10)       NULL,
    폐지일           CHAR(10)       NULL,
    기준일           CHAR(10)       NULL,
    lat              DECIMAL(10,7)  NULL,
    lng              DECIMAL(10,7)  NULL,
    geog             GEOGRAPHY      NULL,
    raw_json         NVARCHAR(MAX)  NULL,         -- 나이별 반·아동 · 근속 등 원문 전부
    is_current       BIT            NOT NULL DEFAULT 1,   -- 그 시군구를 다 받았는데 안 나온 곳 = 0
    loaded_at        DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME()
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'sx_childcare_geog')
    CREATE SPATIAL INDEX sx_childcare_geog ON silver.childcare (geog);
GO
CREATE OR ALTER VIEW gold.v_complex_childcare AS
SELECT c.complex_id, k.stcode, cr_nm = k.이름, cr_type = k.유형, k.상태, k.정원, k.현원, k.반수, k.교직원수, k.통학차량,
       k.제공서비스, k.기준일, k.lat, lon = k.lng, dist_m = c.geog.STDistance(k.geog)
  FROM (SELECT complex_id, geog = geography::Point(centroid_lat, centroid_lng, 4326)
          FROM gold.complex
         WHERE is_active = 1 AND centroid_lat IS NOT NULL AND centroid_lng IS NOT NULL) c
  JOIN silver.childcare k ON k.is_current = 1 AND k.geog IS NOT NULL AND c.geog.STDistance(k.geog) <= 500;
GO
