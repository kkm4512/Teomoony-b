/* 유치원 (유치원알리미, 교육부)  2026-10-19
   ★ 좌표는 geography (미터). 학교·지하철·버스와 같은 방식이다.
     필지/건물/용도지역은 geometry(도) 이고, 거리를 재는 축은 geography 다.
   ★ 공시 데이터라 1년에 2회만 갱신된다. pbnt_tmng(예: 20261 = 2026년 1차)를
     그대로 들고 있어야 화면이 '언제 기준인지' 를 말할 수 있다.
     숫자에 이름을 안 붙이면 보는 사람이 틀린 이름을 붙인다. */
SET NOCOUNT ON;

IF OBJECT_ID('silver.kindergarten') IS NULL
CREATE TABLE silver.kindergarten (
    kinder_cd     VARCHAR(64)   NOT NULL PRIMARY KEY,   -- kindercode (UUID 꼴)
    kinder_nm     NVARCHAR(200) NULL,
    establish     NVARCHAR(40)  NULL,   -- 공립(병설) / 사립(법인) ...
    office_edu    NVARCHAR(60)  NULL,
    suboffice_edu NVARCHAR(60)  NULL,
    sgg_cd        CHAR(5)       NULL,
    addr          NVARCHAR(300) NULL,
    tel_no        NVARCHAR(40)  NULL,
    hp_addr       NVARCHAR(300) NULL,
    oper_time     NVARCHAR(80)  NULL,
    est_date      CHAR(8)       NULL,
    open_date     CHAR(8)       NULL,
    pbnt_tmng     VARCHAR(8)    NULL,   -- 공시 차수. ★ 기준 시점이다
    cap_cnt       INT           NULL,   -- 정원(prmstfcnt)
    pupil_cnt     INT           NULL,   -- 원아 합계(연령별 + 혼합 + 특수)
    class_cnt     INT           NULL,   -- 학급 합계
    lat           DECIMAL(10,7) NULL,
    lng           DECIMAL(10,7) NULL,
    geog          GEOGRAPHY     NULL,
    collected_at  DATE          NULL);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_kinder_sgg')
CREATE INDEX ix_kinder_sgg ON silver.kindergarten (sgg_cd) INCLUDE (kinder_nm, establish);
GO
/* 공간 인덱스 - 반경 질의가 전수 스캔이 되지 않게.
   ★ 공간 연산은 반드시 한쪽을 먼저 좁힌다(11-50). 인덱스는 그 전제다. */
IF NOT EXISTS (SELECT 1 FROM sys.spatial_indexes WHERE name = 'sx_kinder_geog')
CREATE SPATIAL INDEX sx_kinder_geog ON silver.kindergarten (geog);
GO

/* 단지 ↔ 유치원 거리 뷰. 학교/지하철/버스와 같은 꼴로 만든다.
   ★ 500m 로 끊는다 - 유치원은 걸어서 데려다주는 거리다. */
IF OBJECT_ID('gold.v_complex_kinder') IS NOT NULL DROP VIEW gold.v_complex_kinder;
GO
CREATE VIEW gold.v_complex_kinder AS
SELECT c.complex_id,
       k.kinder_cd, k.kinder_nm, k.establish, k.addr, k.tel_no, k.oper_time,
       k.cap_cnt, k.pupil_cnt, k.class_cnt, k.pbnt_tmng,
       dist_m = c.geog.STDistance(k.geog)
  FROM (SELECT complex_id, geog = geography::Point(centroid_lat, centroid_lng, 4326)
          FROM gold.complex
         WHERE is_active = 1 AND centroid_lat IS NOT NULL AND centroid_lng IS NOT NULL) c
  JOIN silver.kindergarten k
    ON k.geog IS NOT NULL
   AND c.geog.STDistance(k.geog) <= 500;
GO
SELECT 결과 = 'silver.kindergarten · gold.v_complex_kinder 준비됨';
