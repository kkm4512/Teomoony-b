/* ============================================================
   290_applyhome : 청약홈 분양정보(한국부동산원) — 공고 · 주택형 · 단지 연결 (2026-10-21, 사장님 "1,2 ㄱㄱ")
   ★ 출처: odcloud ApplyhomeInfoDetailSvc v1 — getAPTLttotPblancDetail(공고) · getAPTLttotPblancMdl(주택형·분양가).
     키 = DATA_GO_KR_KEY(10/18 활용신청됨). 적재 etl/load_applyhome.py (서울 + 경기 중 안양).
   ★ 연결 — **이름으로 잇지 않는다**(정책 1장). 공고 주소의 지번은 **사업 전 지번**이라(합필) PNU 정확일치는 11% 뿐이었다(11-21).
     그래서 코드·좌표로만 이루어진 세 조건이 다 맞고 **후보가 하나**일 때만 잇는다:
       ① 같은 법정동(공고 주소 → meta.lawd_code)
       ② 입주예정월 ±4개월 안에 사용승인(대장 latest_use_apr / K-apt kapt_usedate)
       ③ 단지 세대 ≥ 공급세대(공고는 일반·특별 공급분만 센다 — 재개발이면 전체보다 작다)
       ④ 공고 지번 필지와 단지가 **500m 안**(필지 bbox 중심 ↔ 단지 중심 / K-apt 지번 필지 중심). 필지를 못 찾으면 잇지 않는다.
     ★ 2026-10-21 밤: 500m → **150m**. 표본 41건을 눈으로 보니 0~79m 는 다 맞고, 190m(수서 A-3BL → A-1BL 단지) · 342m(둔촌 현대수린나 → 파크솔레이유)
       · 364m(어반포레 민영 29세대 → 디오르나인) · 403m(에비뉴청계II → 청계로벤하임) 은 **옆 단지**였다. 252m 원베일리 조합원 취소분(1세대)은 맞았지만 잃는다 — 틀리게 잇는 것보다 낫다.
     ④ 가 없으면 같은 달 같은 동에 준공한 **다른 단지**에 붙는다(북서울자이 폴라리스 보류지 6세대 → 엘리프미아역).
   ★ 근거를 남긴다(gold.applyhome_link.근거 · 거리m). 화면은 '추정 연결' 이라고 적는다.
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
IF OBJECT_ID('silver.applyhome_pblanc') IS NULL
CREATE TABLE silver.applyhome_pblanc (
    house_manage_no  VARCHAR(20)    NOT NULL,
    pblanc_no        VARCHAR(20)    NOT NULL,
    house_nm         NVARCHAR(200)  NULL,
    hssply_adres     NVARCHAR(300)  NULL,
    주소_시군구      NVARCHAR(40)   NULL,
    주소_동          NVARCHAR(40)   NULL,
    주소_산          CHAR(1)        NULL,
    주소_본번        VARCHAR(10)    NULL,
    주소_부번        VARCHAR(10)    NULL,
    주소근거         NVARCHAR(40)   NULL,      -- 법정동 그대로 | 행정동 이름에서 숫자 뗌 | 못 품
    lawd_cd          CHAR(10)       NULL,
    pnu              CHAR(19)       NULL,
    house_secd_nm    NVARCHAR(40)   NULL,
    house_dtl_secd_nm NVARCHAR(40)  NULL,
    rent_secd_nm     NVARCHAR(40)   NULL,
    tot_suply        INT            NULL,
    rcrit_pblanc_de  CHAR(10)       NULL,
    rcept_bgnde      CHAR(10)       NULL,
    rcept_endde      CHAR(10)       NULL,
    przwner_de       CHAR(10)       NULL,
    mvn_prearnge_ym  CHAR(6)        NULL,
    bsns_mby_nm      NVARCHAR(200)  NULL,
    cnstrct_entrps_nm NVARCHAR(200) NULL,
    pblanc_url       NVARCHAR(400)  NULL,
    subscrpt_area_nm NVARCHAR(20)   NULL,
    raw_json         NVARCHAR(MAX)  NULL,
    loaded_at        DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_applyhome_pblanc PRIMARY KEY CLUSTERED (house_manage_no, pblanc_no)
);
GO
IF OBJECT_ID('silver.applyhome_mdl') IS NULL
CREATE TABLE silver.applyhome_mdl (
    house_manage_no  VARCHAR(20)    NOT NULL,
    pblanc_no        VARCHAR(20)    NOT NULL,
    model_no         VARCHAR(10)    NOT NULL,
    house_ty         NVARCHAR(40)   NULL,      -- '084.9700A' — 앞 8자리가 전용면적(4-x)
    전용m2           DECIMAL(9,4)   NULL,
    suply_ar         DECIMAL(12,4)  NULL,      -- 공급면적
    suply_hshldco    INT            NULL,      -- 일반공급
    spsply_hshldco   INT            NULL,      -- 특별공급
    top_amount_man   BIGINT         NULL,      -- 분양최고금액(만원, 원문)
    raw_json         NVARCHAR(MAX)  NULL,
    loaded_at        DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_applyhome_mdl PRIMARY KEY CLUSTERED (house_manage_no, pblanc_no, model_no)
);
GO
IF OBJECT_ID('gold.applyhome_link') IS NULL
CREATE TABLE gold.applyhome_link (
    house_manage_no  VARCHAR(20)    NOT NULL,
    pblanc_no        VARCHAR(20)    NOT NULL,
    complex_id       INT            NULL,
    kapt_code        VARCHAR(20)    NULL,
    근거             NVARCHAR(200)  NOT NULL,
    거리m            INT            NULL,
    굳힌시각         DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_applyhome_link PRIMARY KEY CLUSTERED (house_manage_no, pblanc_no)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_applyhome_link_cid')
    CREATE INDEX ix_applyhome_link_cid ON gold.applyhome_link (complex_id) WHERE complex_id IS NOT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_applyhome_link_kapt')
    CREATE INDEX ix_applyhome_link_kapt ON gold.applyhome_link (kapt_code) WHERE kapt_code IS NOT NULL;
GO
CREATE OR ALTER PROCEDURE gold.usp_refresh_applyhome_link
AS
BEGIN
    SET NOCOUNT ON;
    /* 296: 법정동 못 찾은 공고 — 동 이름으로 다시, 도로명이면 대장 도로명과 대조(후보 1일 때만) */
    IF OBJECT_ID('gold.usp_applyhome_road_to_jibun') IS NOT NULL EXEC gold.usp_applyhome_road_to_jibun;

    /* PNU 는 조각에서 한 자리(meta.fn_make_pnu)에서만 만든다(정책 1장) */
    UPDATE p SET pnu = meta.fn_make_pnu(LEFT(p.lawd_cd,5), RIGHT(p.lawd_cd,5), ISNULL(p.주소_산,'0'), p.주소_본번, ISNULL(p.주소_부번,'0'))
      FROM silver.applyhome_pblanc p WHERE p.lawd_cd IS NOT NULL AND p.주소_본번 IS NOT NULL;

    IF OBJECT_ID('tempdb..#p') IS NOT NULL DROP TABLE #p;
    SELECT p.house_manage_no, p.pblanc_no, p.lawd_cd, p.pnu, p.tot_suply,
           ym0 = CONVERT(char(6), DATEADD(MONTH, -4, TRY_CONVERT(date, p.mvn_prearnge_ym + '01')), 112),
           ym1 = CONVERT(char(6), DATEADD(MONTH,  4, TRY_CONVERT(date, p.mvn_prearnge_ym + '01')), 112),
           plat = (cp.bbox_miny + cp.bbox_maxy) / 2, plng = (cp.bbox_minx + cp.bbox_maxx) / 2
      INTO #p
      FROM silver.applyhome_pblanc p
      LEFT JOIN silver.cadastral_parcel cp ON cp.pnu = p.pnu AND cp.is_current = 1
     WHERE p.lawd_cd IS NOT NULL AND p.mvn_prearnge_ym IS NOT NULL;

    /* 후보 — 대장 단지 */
    IF OBJECT_ID('tempdb..#c') IS NOT NULL DROP TABLE #c;
    SELECT p.house_manage_no, p.pblanc_no, c.complex_id,
           m = geography::Point(p.plat, p.plng, 4326).STDistance(geography::Point(c.centroid_lat, c.centroid_lng, 4326))
      INTO #c
      FROM #p p JOIN gold.complex c
        ON c.merged_into IS NULL AND c.sigungu_cd = LEFT(p.lawd_cd, 5) AND c.bjdong_cd = RIGHT(p.lawd_cd, 5)
       AND c.hhld_cnt_sum >= p.tot_suply AND LEFT(c.latest_use_apr, 6) BETWEEN p.ym0 AND p.ym1
       AND c.centroid_lat IS NOT NULL
     WHERE p.plat IS NOT NULL;
    DELETE FROM #c WHERE m > 100;   /* 2026-10-21 22:30 500→150 (표본 41 중 190·342·364·403m 넷이 옆 단지였다)
                                       2026-10-22 10:20 150→100 (도시형 넣고 보니 114m 상봉 유보라→와이센트럴 · 130m 힐스테이트청량리→롯데캐슬 Sky-L65 가 옆 단지. 맞은 것은 최대 79m) */
    /* 2026-10-21 밤: 공고 지번이 **이미 다른 단지의 필지**면 그 공고를 그 단지 아닌 곳에 잇지 않는다.
       '신성안양미소지움 공가세대(재건축매입 임대 공가)' 는 기존 아파트 주소라 입주월 창에 걸린 옆 신축(더베이타운 57m)에 붙었다. */
    DELETE c FROM #c c JOIN #p p ON p.house_manage_no = c.house_manage_no AND p.pblanc_no = c.pblanc_no
     WHERE p.pnu IS NOT NULL
       AND EXISTS (SELECT 1 FROM gold.complex_pnu cp JOIN gold.complex x ON x.complex_id = cp.complex_id AND x.merged_into IS NULL
                    WHERE cp.pnu = p.pnu AND cp.complex_id <> c.complex_id)
       AND NOT EXISTS (SELECT 1 FROM gold.complex_pnu cp WHERE cp.pnu = p.pnu AND cp.complex_id = c.complex_id);

    /* 후보 — K-apt(대장 없는 신축 포함) */
    IF OBJECT_ID('tempdb..#k') IS NOT NULL DROP TABLE #k;
    SELECT p.house_manage_no, p.pblanc_no, k.kapt_code,
           m = geography::Point(p.plat, p.plng, 4326).STDistance(
                 geography::Point((kp.bbox_miny + kp.bbox_maxy) / 2, (kp.bbox_minx + kp.bbox_maxx) / 2, 4326))
      INTO #k
      FROM #p p JOIN silver.kapt_complex k
        ON k.is_current = 1 AND k.bjd_code = p.lawd_cd AND k.ho_cnt >= p.tot_suply
       AND LEFT(k.kapt_usedate, 6) BETWEEN p.ym0 AND p.ym1
      JOIN silver.cadastral_parcel kp ON kp.pnu = k.pnu AND kp.is_current = 1
     WHERE p.plat IS NOT NULL;
    DELETE FROM #k WHERE m > 100;

    BEGIN TRAN;
        DELETE FROM gold.applyhome_link;
        /* 대장 후보가 정확히 하나 */
        INSERT INTO gold.applyhome_link (house_manage_no, pblanc_no, complex_id, kapt_code, 근거, 거리m)
        SELECT c.house_manage_no, c.pblanc_no, MIN(c.complex_id),
               (SELECT TOP 1 ck.kapt_code FROM gold.complex_kapt ck WHERE ck.complex_id = MIN(c.complex_id)),
               N'법정동·입주월±4·세대·100m — 대장 후보 1', CAST(MIN(c.m) AS INT)
          FROM #c c GROUP BY c.house_manage_no, c.pblanc_no HAVING COUNT(DISTINCT c.complex_id) = 1;
        /* 대장엔 없고 K-apt 후보가 정확히 하나 */
        INSERT INTO gold.applyhome_link (house_manage_no, pblanc_no, complex_id, kapt_code, 근거, 거리m)
        SELECT k.house_manage_no, k.pblanc_no,
               (SELECT TOP 1 ck.complex_id FROM gold.complex_kapt ck WHERE ck.kapt_code = MIN(k.kapt_code)),
               MIN(k.kapt_code), N'법정동·입주월±4·세대·100m — K-apt 후보 1', CAST(MIN(k.m) AS INT)
          FROM #k k
         WHERE NOT EXISTS (SELECT 1 FROM gold.applyhome_link l WHERE l.house_manage_no = k.house_manage_no AND l.pblanc_no = k.pblanc_no)
         GROUP BY k.house_manage_no, k.pblanc_no HAVING COUNT(DISTINCT k.kapt_code) = 1;
    COMMIT;

    SELECT 공고 = (SELECT COUNT(*) FROM silver.applyhome_pblanc),
           법정동 = (SELECT COUNT(*) FROM silver.applyhome_pblanc WHERE lawd_cd IS NOT NULL),
           필지 = (SELECT COUNT(*) FROM #p WHERE plat IS NOT NULL),
           이음 = (SELECT COUNT(*) FROM gold.applyhome_link),
           단지에 = (SELECT COUNT(*) FROM gold.applyhome_link WHERE complex_id IS NOT NULL),
           신축에 = (SELECT COUNT(*) FROM gold.applyhome_link WHERE complex_id IS NULL AND kapt_code IS NOT NULL);
END
GO
