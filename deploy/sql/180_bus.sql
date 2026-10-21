/* 180. 버스정류소 (2026-10-19)
   출처: 국토교통부_(TAGO)_버스정류소정보 (data.go.kr 15096280, 전국버스정류소표준데이터)
         서비스 URL https://apis.data.go.kr/1613000/BusSttnInfoInqireService
         **이용허락범위 제한 없음** · 자동승인 · 개발계정 10,000건/일
         ※ 1613000 은 건축HUB와 같은 기관코드지만 **API 별로 활용신청이 따로**다.

   ★ 자연키는 (city_code, node_id) 다
     node_id 가 'DJB8001793' 처럼 도시 접두어를 달고 오지만, 전국에서 유일하다는
     **보장은 어디에도 없다.** 도시코드를 같이 묶어 둔다 - 나중에 겹치는 걸
     발견하는 것보다 지금 안 겹치게 두는 게 싸다.

   ★ 거리는 geography. semas_store / school 과 같은 이유다(미터).

   ★ 여기엔 '어느 버스가 서는가' 가 없다
     경유노선은 `getSttnThrghRouteList` 로 **정류소마다 한 번씩** 불러야 한다.
     정류소가 수만 개라 지금은 안 받는다. 받기 전까지 화면에서
     "몇 번 버스" 를 말하지 않는다 - 모르는 걸 아는 척하지 않는다.
*/
IF OBJECT_ID('silver.bus_stop') IS NULL
CREATE TABLE silver.bus_stop (
    stop_sk       BIGINT IDENTITY(1,1) NOT NULL,
    city_code     VARCHAR(10)    NOT NULL,   -- TAGO 도시코드 (자체 체계)
    city_nm       NVARCHAR(60)   NULL,
    node_id       VARCHAR(40)    NOT NULL,   -- 정류소ID
    node_nm       NVARCHAR(120)  NULL,       -- 정류소명
    node_no       VARCHAR(20)    NULL,       -- 정류소번호 (승강장 번호)
    lat           DECIMAL(11,8)  NULL,
    lon           DECIMAL(12,8)  NULL,
    geog          geography      NULL,       -- SRID 4326
    collected_at  CHAR(8)        NULL,
    row_hash      BINARY(32)     NOT NULL,
    valid_from    DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    valid_to      DATETIME2(0)   NOT NULL DEFAULT '9999-12-31',
    is_current    BIT            NOT NULL DEFAULT 1,
    CONSTRAINT pk_bus_stop PRIMARY KEY CLUSTERED (stop_sk)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='uq_bus_stop_current')
CREATE UNIQUE INDEX uq_bus_stop_current ON silver.bus_stop (city_code, node_id)
    WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='sx_bus_stop_geog')
CREATE SPATIAL INDEX sx_bus_stop_geog ON silver.bus_stop (geog);
GO
PRINT '180 완료 - silver.bus_stop';
