/* 187. 버스 노선 · 노선별 경유 정류장 (2026-10-19)
   출처: 서울특별시_노선정보조회 서비스 (data.go.kr 15000193)
         http://ws.bus.go.kr/api/rest/busRouteInfo/...
         **공공누리 1유형(출처표시)** · 개발계정 1,000건/일

   ★ 왜 '노선 기준' 인가 — 호출을 줄이려고
     '이 정류장에 몇 번이 서나' 를 정류장마다 물으면 서울 13,010 승강장 ×1 이다.
     노선마다 물으면 **1,352회**로 전부 덮인다. 상권에서 배운 것과 같다
     (반경마다 부르지 말고 영역 한 번에 받기 - 133회 → 2회).

   ★ 그래도 하루 한도(1,000)를 넘는다 → **이어받기**로 만든다.
     이미 받은 노선은 건너뛰고, 한도에 걸리면 **거기까지 저장하고 깨끗이 멈춘다.**
     우선순위: 간선·지선·마을 → 광역·심야·순환·공항 → 경기·인천.

   ★ routeType 은 추측하지 않고 실측했다(노선명으로 확인):
     1 공항 · 2 마을 · 3 간선 · 4 지선 · 5 순환 · 6 광역 · 7 인천 ·
     8 경기 · 10 관광 · 14 한강버스 · 15 심야(N)

   ★ arsId 로 우리 정류장과 붙는다 — `silver.bus_stop.ars_no` 와 같은 번호다.
     정류장ID(station)는 서울시 자체 체계라 국토부 파일과 직접 안 맞는다.
*/
IF OBJECT_ID('silver.bus_route') IS NULL
CREATE TABLE silver.bus_route (
    route_id      VARCHAR(20)    NOT NULL,
    route_nm      NVARCHAR(60)   NULL,
    route_abrv    NVARCHAR(60)   NULL,
    route_type    VARCHAR(4)     NULL,
    st_station_nm NVARCHAR(120)  NULL,
    ed_station_nm NVARCHAR(120)  NULL,
    term          VARCHAR(10)    NULL,       -- 배차간격(분)
    corp_nm       NVARCHAR(120)  NULL,
    first_bus_tm  VARCHAR(20)    NULL,
    last_bus_tm   VARCHAR(20)    NULL,
    collected_at  CHAR(8)        NULL,
    CONSTRAINT pk_bus_route PRIMARY KEY CLUSTERED (route_id)
);
GO
IF OBJECT_ID('silver.bus_route_station') IS NULL
CREATE TABLE silver.bus_route_station (
    route_id      VARCHAR(20)    NOT NULL,
    seq           INT            NOT NULL,   -- 노선 안 순번
    station_id    VARCHAR(20)    NULL,       -- 서울시 정류장ID
    ars_no        VARCHAR(20)    NULL,       -- ★ 우리 bus_stop.ars_no 와 조인
    station_nm    NVARCHAR(200)  NULL,
    direction     NVARCHAR(120)  NULL,
    lon           DECIMAL(12,8)  NULL,
    lat           DECIMAL(11,8)  NULL,
    collected_at  CHAR(8)        NULL,
    CONSTRAINT pk_bus_route_station PRIMARY KEY CLUSTERED (route_id, seq)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_brs_ars')
CREATE INDEX ix_brs_ars ON silver.bus_route_station (ars_no) INCLUDE (route_id);
GO
PRINT '187 완료 - silver.bus_route / silver.bus_route_station';
