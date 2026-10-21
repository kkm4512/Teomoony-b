/* 188. 초등학교 통학구역(학구도) (2026-10-19)
   출처: 한국교육시설안전원_초등학교통학구역 (data.go.kr 15159265)
         SHP · 전국 7,132개 · **이용허락범위 제한 없음** · 기준일 2026-09-20
         ※ 학구도 공공데이터 7종은 매년 3월·9월 배포.
         ※ `silver.school`(초중등학교위치)과 **같은 기관**이다.

   ★ 왜 필요한가 — 거리로 학군을 말하면 그럴듯하게 틀린다
     지금 화면은 "가장 가까운 초등학교 421m" 만 말하고
     "배정과는 다르다" 고 적어 두었다. 통학구역은 교육지원청이 정하고,
     길 하나 건너면 갈리는 일이 흔하다. **이 폴리곤이 그 답이다.**

   ★ 좌표계: 원본은 EPSG:5186(Korea 2000 중부원점). **4326 으로 바꿔서** 넣는다
     (변환은 받을 때 한 번, data/README 참고). 용도지역·정비구역과 같은 방식이다.

   ★ HAKGUDO_GB : '0' 단독 통학구역 / '1' 공동통학구역
     공동통학구역은 이름에 학교가 둘 이상 들어온다
     (예: '서울광희초서울창신초공동통학구역'). **하나로 우겨넣지 않는다.**

   ★ 학구명에 학교명이 들어 있지만 **학교ID 는 없다.**
     '서울녹번초통학구역' -> '서울녹번초등학교' 는 문자열 규칙이라
     틀릴 수 있다. 매칭은 **참고로만** 쓰고, 화면에는 학구명을 그대로 보여준다.
*/
IF OBJECT_ID('silver.school_zone') IS NULL
CREATE TABLE silver.school_zone (
    zone_sk       BIGINT IDENTITY(1,1) NOT NULL,
    hakgudo_id    VARCHAR(20)    NOT NULL,
    hakgudo_nm    NVARCHAR(254)  NULL,
    hakgudo_gb    CHAR(1)        NULL,       -- 0 단독 / 1 공동
    sd_cd         CHAR(2)        NULL,
    sgg_cd        CHAR(3)        NULL,
    edu_nm        NVARCHAR(60)   NULL,
    base_dt       CHAR(10)       NULL,
    geom          geometry       NULL,       -- SRID 4326
    bbox_minx     DECIMAL(12,8)  NULL,
    bbox_miny     DECIMAL(11,8)  NULL,
    bbox_maxx     DECIMAL(12,8)  NULL,
    bbox_maxy     DECIMAL(11,8)  NULL,
    collected_at  CHAR(8)        NULL,
    CONSTRAINT pk_school_zone PRIMARY KEY CLUSTERED (zone_sk)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='uq_school_zone')
CREATE UNIQUE INDEX uq_school_zone ON silver.school_zone (hakgudo_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='sx_school_zone')
CREATE SPATIAL INDEX sx_school_zone ON silver.school_zone (geom)
    USING GEOMETRY_AUTO_GRID WITH (BOUNDING_BOX = (126.7, 37.4, 127.2, 37.7));
GO
PRINT '188 완료 - silver.school_zone';
