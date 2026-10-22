/* ============================================================
   312_ask_attr : AI 검색 조건용 **단지 속성 요약** (2026-10-22, 사장님 "AI 검색 고도화 1번 — 가진 데이터로 조건 늘리기")
   ★ 왜: AI 검색에 평형 · 역 거리 · 학교 거리 · 정비구역 · 용도지역 조건을 붙인다. 이 사실들은 단지 상세가 이미
     뷰(v_complex_subway · v_complex_school · v_complex_redev · v_complex_zone · 호 전유면적)로 **단지 하나씩** 센다.
     그런데 뷰를 조건 없이 훑으면 53만 단지 × 공간계산이라 10분이 넘는다(179 주석). 검색은 "조건에 맞는 단지 전부"를
     물으므로, **같은 식 · 같은 거르기**로 단지마다 한 번 세어 둔다 — 288(complex_trade_max)과 같은 '요약'이다.
   ★ 같은 사실은 한 곳에서: 거리 = 같은 geography STDistance(단지 중심점), 반경 = 뷰와 같은 1.5km(역) · 2km(학교),
     정비 · 용도 = 같은 필지 × 구역 교차, 비중 = 상세와 같은 SUM(교차)/SUM(필지). 다른 것은 **미리 거르는 칸(격자)** 뿐이고
     격자는 반경보다 넓어 결과를 바꾸지 않는다.
   ★ 원본은 건드리지 않는다 — 여기 표는 전부 파생표다(지우고 다시 세도 원본이 그대로면 같은 값이 나온다).
   ★ 다시 세는 때: 단지(gold.complex) 재구성 · 역/학교/정비/용도/대장/실거래 적재 뒤. gold.usp_refresh_ask_attr.
     얼마나 묵었는지는 gold.ask_attr_meta.굳힌때 로 화면에 적는다.
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
IF OBJECT_ID('gold.ask_attr_meta') IS NULL
CREATE TABLE gold.ask_attr_meta (
    표       VARCHAR(20)  NOT NULL PRIMARY KEY,
    굳힌때   DATETIME2(0) NOT NULL,
    행수     INT          NULL
);
/* 호 전유면적(대장) — 단지 상세 동·호 격자와 같은 식: 호PK 의 전유(구분 '1') 면적 합. 주거 호만(아파트·연립·다세대·오피스텔). */
IF OBJECT_ID('gold.complex_area') IS NULL
CREATE TABLE gold.complex_area (
    complex_id INT           NOT NULL,
    전용       DECIMAL(9,2)  NOT NULL,
    호수       INT           NOT NULL,
    CONSTRAINT pk_complex_area PRIMARY KEY CLUSTERED (complex_id, 전용)
);
/* 실거래 전용면적별 최고 매매가 — 288 과 같은 규칙(매매 · 해제 제외 · 금액 있음), 면적별로 */
IF OBJECT_ID('gold.complex_area_trade') IS NULL
CREATE TABLE gold.complex_area_trade (
    종류       VARCHAR(4)    NOT NULL,
    complex_id INT           NOT NULL,
    전용       DECIMAL(9,2)  NOT NULL,
    max_amt    BIGINT        NOT NULL,
    n          INT           NOT NULL,
    CONSTRAINT pk_complex_area_trade PRIMARY KEY CLUSTERED (종류, complex_id, 전용)
);
IF OBJECT_ID('gold.complex_station') IS NULL
CREATE TABLE gold.complex_station (
    complex_id INT           NOT NULL,
    sttn_nm    NVARCHAR(100) NULL,
    line_nm    NVARCHAR(100) NULL,
    dist_m     FLOAT         NOT NULL
);
IF OBJECT_ID('gold.complex_school_near') IS NULL
CREATE TABLE gold.complex_school_near (
    complex_id INT           NOT NULL,
    school_se  NVARCHAR(20)  NOT NULL,
    school_nm  NVARCHAR(200) NULL,
    dist_m     FLOAT         NOT NULL,
    CONSTRAINT pk_complex_school_near PRIMARY KEY CLUSTERED (complex_id, school_se)
);
IF OBJECT_ID('gold.complex_redev_hit') IS NULL
CREATE TABLE gold.complex_redev_hit (
    complex_id INT           NOT NULL,
    present_sn VARCHAR(40)   NOT NULL,
    xarea      FLOAT         NULL,
    parea      FLOAT         NULL,
    CONSTRAINT pk_complex_redev_hit PRIMARY KEY CLUSTERED (complex_id, present_sn)
);
IF OBJECT_ID('gold.complex_zone_hit') IS NULL
CREATE TABLE gold.complex_zone_hit (
    complex_id INT           NOT NULL,
    uname      NVARCHAR(100) NOT NULL,
    xarea      FLOAT         NULL,
    CONSTRAINT pk_complex_zone_hit PRIMARY KEY CLUSTERED (complex_id, uname)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'cx_complex_station')
    CREATE CLUSTERED INDEX cx_complex_station ON gold.complex_station (complex_id, dist_m);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_cat_area')
    CREATE INDEX ix_cat_area ON gold.complex_area_trade (종류, 전용) INCLUDE (complex_id, max_amt);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_carea_area')
    CREATE INDEX ix_carea_area ON gold.complex_area (전용) INCLUDE (호수);
GO
CREATE OR ALTER PROCEDURE gold.usp_ask_attr_build @what VARCHAR(10), @a INT, @b INT
WITH RECOMPILE   -- 범위마다 단지 수가 달라 계획을 다시 세운다(첫 범위 계획이 굳으면 작은 범위도 60초를 넘겼다)
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;   -- 적재 중 표의 잠금을 기다리지 않는다(11-145)

    IF @what = 'area'
    BEGIN
        /* 호 목록을 먼저 뽑고, 면적표는 **한 번 훑어** 호마다 합친다(해시).
           호마다 찾아가면(APPLY) 5,000단지에 무작위 읽기 수십만 번이라 60초를 넘겼다 — 적재가 디스크를 쓰는 중이면 더. */
        IF OBJECT_ID('tempdb..#h') IS NOT NULL DROP TABLE #h;
        SELECT DISTINCT h.complex_id, h.호PK INTO #h FROM gold.v_complex_ho h WHERE h.complex_id BETWEEN @a AND @b;
        DELETE FROM gold.complex_area WHERE complex_id BETWEEN @a AND @b;
        INSERT INTO gold.complex_area (complex_id, 전용, 호수)
        SELECT h.complex_id, x.전용, COUNT(*)
          FROM #h h
          JOIN (SELECT a.mgm_bldrgst_pk,
                       전용 = CAST(SUM(a.area) AS DECIMAL(9,2)),
                       주거 = MAX(CASE WHEN a.main_purps_cd IN ('02001','02002','02003','14202') THEN 1 ELSE 0 END)
                  FROM silver.bld_expos_pubuse_area a
                 WHERE a.is_current = 1 AND a.expos_pubuse_gb_cd = '1'
                 GROUP BY a.mgm_bldrgst_pk) x ON x.mgm_bldrgst_pk = h.호PK
         WHERE x.주거 = 1 AND x.전용 > 0
         GROUP BY h.complex_id, x.전용
        OPTION (HASH JOIN);
    END

    IF @what = 'atrade'
    BEGIN
        DELETE FROM gold.complex_area_trade WHERE complex_id BETWEEN @a AND @b;
        INSERT INTO gold.complex_area_trade (종류, complex_id, 전용, max_amt, n)
        SELECT g.종류, r.match_complex_id, CAST(r.exclu_use_ar AS DECIMAL(9,2)), MAX(r.deal_amount), COUNT(*)
          FROM silver.rtms_trade r
         CROSS APPLY (SELECT 'ALL' UNION ALL
                      SELECT CASE WHEN r.trade_kind IN ('APT_TRADE_DEV','APT_TRADE') THEN 'APT'
                                  WHEN r.trade_kind LIKE 'RH_%' THEN 'RH'
                                  WHEN r.trade_kind LIKE 'OFFI_%' THEN 'OFFI' END) g(종류)
         WHERE r.match_complex_id BETWEEN @a AND @b AND r.is_rent = 0 AND r.is_canceled = 0
           AND r.deal_amount IS NOT NULL AND r.exclu_use_ar > 0 AND g.종류 IS NOT NULL
         GROUP BY g.종류, r.match_complex_id, CAST(r.exclu_use_ar AS DECIMAL(9,2));
    END

    IF @what IN ('station', 'school')
    BEGIN
        /* 격자: 위도 0.02°(2.2km) × 경도 0.025°(위도 38.6° 에서도 2.17km) — 반경(1.5km · 2km)보다 넓다.
           이웃 9칸만 보면 반경 안의 점은 하나도 빠지지 않는다. 거리 자체는 뷰와 같은 식으로 다시 잰다. */
        IF OBJECT_ID('tempdb..#c') IS NOT NULL DROP TABLE #c;
        SELECT c.complex_id, c.centroid_lat, c.centroid_lng,
               gy = CAST(FLOOR(c.centroid_lat / 0.02) AS INT) + dy.v,
               gx = CAST(FLOOR(c.centroid_lng / 0.025) AS INT) + dx.v
          INTO #c
          FROM gold.complex c
         CROSS JOIN (VALUES (-1), (0), (1)) dy(v)
         CROSS JOIN (VALUES (-1), (0), (1)) dx(v)
         WHERE c.is_active = 1 AND c.centroid_lat IS NOT NULL AND c.complex_id BETWEEN @a AND @b;

        IF @what = 'station'
        BEGIN
            DELETE FROM gold.complex_station WHERE complex_id BETWEEN @a AND @b;
            INSERT INTO gold.complex_station (complex_id, sttn_nm, line_nm, dist_m)
            SELECT c.complex_id, s.sttn_nm, s.line_nm, d.dist_m
              FROM #c c
              JOIN (SELECT sttn_nm, line_nm, geog,
                           gy = CAST(FLOOR(lat / 0.02) AS INT), gx = CAST(FLOOR(lon / 0.025) AS INT)
                      FROM silver.subway_station WHERE is_current = 1 AND geog IS NOT NULL) s
                ON s.gy = c.gy AND s.gx = c.gx
             CROSS APPLY (SELECT dist_m = s.geog.STDistance(geography::Point(c.centroid_lat, c.centroid_lng, 4326))) d
             WHERE d.dist_m <= 1500;
        END
        ELSE
        BEGIN
            DELETE FROM gold.complex_school_near WHERE complex_id BETWEEN @a AND @b;
            INSERT INTO gold.complex_school_near (complex_id, school_se, school_nm, dist_m)
            SELECT complex_id, school_se, school_nm, dist_m
              FROM (SELECT c.complex_id, s.school_se, s.school_nm, d.dist_m,
                           rn = ROW_NUMBER() OVER (PARTITION BY c.complex_id, s.school_se ORDER BY d.dist_m, s.school_nm)
                      FROM #c c
                      JOIN (SELECT school_se, school_nm, geog,
                                   gy = CAST(FLOOR(lat / 0.02) AS INT), gx = CAST(FLOOR(lon / 0.025) AS INT)
                              FROM silver.school
                             WHERE is_current = 1 AND geog IS NOT NULL AND oper_sttus = N'운영' AND school_se IS NOT NULL) s
                        ON s.gy = c.gy AND s.gx = c.gx
                     CROSS APPLY (SELECT dist_m = s.geog.STDistance(geography::Point(c.centroid_lat, c.centroid_lng, 4326))) d
                     WHERE d.dist_m <= 2000) x
             WHERE rn = 1;
        END
    END

    IF @what = 'redev'
    BEGIN
        DELETE FROM gold.complex_redev_hit WHERE complex_id BETWEEN @a AND @b;
        INSERT INTO gold.complex_redev_hit (complex_id, present_sn, xarea, parea)
        SELECT cp.complex_id, r.present_sn,
               SUM(p.geom.STIntersection(r.geom).STArea()), SUM(p.geom.STArea())
          FROM gold.complex_pnu cp
          JOIN silver.cadastral_parcel p
            ON p.pnu = cp.pnu AND p.is_current = 1 AND p.geom IS NOT NULL
          JOIN silver.redev_zone r
            ON r.is_current = 1 AND r.geom IS NOT NULL
           AND r.bbox_minx <= p.bbox_maxx AND r.bbox_maxx >= p.bbox_minx
           AND r.bbox_miny <= p.bbox_maxy AND r.bbox_maxy >= p.bbox_miny
           AND r.geom.STIntersects(p.geom) = 1
         WHERE cp.complex_id BETWEEN @a AND @b
         GROUP BY cp.complex_id, r.present_sn;
    END

    IF @what = 'zone'
    BEGIN
        DELETE FROM gold.complex_zone_hit WHERE complex_id BETWEEN @a AND @b;
        INSERT INTO gold.complex_zone_hit (complex_id, uname, xarea)
        SELECT cp.complex_id, z.uname, SUM(p.geom.STIntersection(z.geom).STArea())
          FROM gold.complex_pnu cp
          JOIN silver.cadastral_parcel p
            ON p.pnu = cp.pnu AND p.is_current = 1 AND p.geom IS NOT NULL
          JOIN silver.land_use_zone z
            ON z.is_current = 1 AND z.geom IS NOT NULL
           AND LTRIM(ISNULL(z.uname, '')) <> ''        -- 대분류 폴리곤 제외 (v_complex_zone 과 같게)
           AND z.bbox_minx <= p.bbox_maxx AND z.bbox_maxx >= p.bbox_minx
           AND z.bbox_miny <= p.bbox_maxy AND z.bbox_maxy >= p.bbox_miny
           AND z.geom.STIntersects(p.geom) = 1
         WHERE cp.complex_id BETWEEN @a AND @b
         GROUP BY cp.complex_id, z.uname;
    END

    DECLARE @표 VARCHAR(20) = CASE @what WHEN 'area' THEN 'complex_area' WHEN 'atrade' THEN 'complex_area_trade'
                               WHEN 'station' THEN 'complex_station' WHEN 'school' THEN 'complex_school_near'
                               WHEN 'redev' THEN 'complex_redev_hit' WHEN 'zone' THEN 'complex_zone_hit' END;
    IF @표 IS NULL RETURN;
    MERGE gold.ask_attr_meta AS t
    USING (SELECT 표 = @표) s ON t.표 = s.표
    WHEN MATCHED THEN UPDATE SET 굳힌때 = SYSDATETIME()
    WHEN NOT MATCHED THEN INSERT (표, 굳힌때) VALUES (s.표, SYSDATETIME());
END
GO
/* 전부 다시 세기(적재 뒤 일꾼이 부른다) — 범위를 나눠 돈다. 화면이 묵은 정도를 알도록 행수를 적는다. */
CREATE OR ALTER PROCEDURE gold.usp_refresh_ask_attr @what VARCHAR(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @mx INT = (SELECT MAX(complex_id) FROM gold.complex), @a INT, @b INT, @step INT;
    DECLARE @w TABLE (k VARCHAR(10), step INT);
    INSERT INTO @w VALUES ('area', 1000000), ('atrade', 40000), ('station', 40000), ('school', 40000), ('redev', 20000), ('zone', 20000);
    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT k, step FROM @w WHERE @what IS NULL OR k = @what;
    DECLARE @k VARCHAR(10);
    OPEN cur; FETCH NEXT FROM cur INTO @k, @step;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @a = 0;
        WHILE @a <= @mx BEGIN SET @b = @a + @step - 1; EXEC gold.usp_ask_attr_build @k, @a, @b; SET @a += @step; END
        FETCH NEXT FROM cur INTO @k, @step;
    END
    CLOSE cur; DEALLOCATE cur;
    EXEC gold.usp_ask_attr_count;
END
GO
CREATE OR ALTER PROCEDURE gold.usp_ask_attr_count
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE m SET 행수 = x.n FROM gold.ask_attr_meta m
      JOIN (SELECT 표 = 'complex_area', n = COUNT(*) FROM gold.complex_area
            UNION ALL SELECT 'complex_area_trade', COUNT(*) FROM gold.complex_area_trade
            UNION ALL SELECT 'complex_station', COUNT(*) FROM gold.complex_station
            UNION ALL SELECT 'complex_school_near', COUNT(*) FROM gold.complex_school_near
            UNION ALL SELECT 'complex_redev_hit', COUNT(*) FROM gold.complex_redev_hit
            UNION ALL SELECT 'complex_zone_hit', COUNT(*) FROM gold.complex_zone_hit) x ON x.표 = m.표;
END
GO
