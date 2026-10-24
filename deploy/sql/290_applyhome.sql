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
        /* 2026-10-22 23:31 사장님 "매칭 #3": 공고 지번이 **그대로 단지의 필지**이고 그 단지가 **공고 뒤에 준공**(사용승인 ≥ 모집공고일)된
           세대 단지가 딱 하나면 그 단지 — 거리·입주월 창이 필요 없다(지번이 같다). 철거 전 옛 단지는 '공고 뒤 준공' 이 아니라 끼어들 수 없다.
           실측: 전국 89건 중 64건은 위 두 길과 **같은 단지**(다른 단지 0) · 25건이 새로 이어짐(마곡 엠밸리 9단지 · 원에디션 강남 · 에비뉴 청계 Ⅰ·Ⅱ …).
           ★ 법정동·입주월·세대만으로 하나인 후보(거리 없이)는 쓰지 않는다 — 이 길과 겹친 8건 중 7건이 **다른 단지**였다. */
        INSERT INTO gold.applyhome_link (house_manage_no, pblanc_no, complex_id, kapt_code, 근거, 거리m)
        SELECT p.house_manage_no, p.pblanc_no, MIN(c.complex_id),
               (SELECT TOP 1 ck.kapt_code FROM gold.complex_kapt ck WHERE ck.complex_id = MIN(c.complex_id)),
               N'공고 지번 = 단지 필지 · 공고 뒤 준공 — 대장 후보 1', 0
          FROM silver.applyhome_pblanc p
          JOIN gold.complex_pnu cp ON cp.pnu = p.pnu
          JOIN gold.complex c ON c.complex_id = cp.complex_id AND c.is_active = 1 AND c.merged_into IS NULL AND c.hhld_cnt_sum > 0
         WHERE LEN(c.oldest_use_apr) = 8 AND c.oldest_use_apr >= REPLACE(p.rcrit_pblanc_de, '-', '')
           AND NOT EXISTS (SELECT 1 FROM gold.applyhome_link l WHERE l.house_manage_no = p.house_manage_no AND l.pblanc_no = p.pblanc_no)
         GROUP BY p.house_manage_no, p.pblanc_no HAVING COUNT(DISTINCT c.complex_id) = 1;
        /* 2026-10-23 사장님 "확실한건만 · ㄱㄱ"(11-224): 공고 지번 = **K-apt 지번**(둘 다 사업 전 지번 그대로인 곳이 많다) · 그 지번의 K-apt 가 **하나**.
           ① 그 K-apt 가 대장 단지에 이어져 있고(317·321 코드) 그 단지가 공고 뒤 준공 → 그 단지
           ② 그 K-apt 가 대장이 아직 없는 신축이고 K-apt 사용승인이 공고 뒤(또는 비어 있음) → 그 K-apt(신축 핀)
           공고 지번이 지적도에서 사라진 곳(합필·환지)이나 대장이 아직 안 들어온 새 단지가 이 길로 이어진다. 이름은 안 본다. */
        INSERT INTO gold.applyhome_link (house_manage_no, pblanc_no, complex_id, kapt_code, 근거, 거리m)
        SELECT p.house_manage_no, p.pblanc_no, x.complex_id, x.kapt_code,
               CASE WHEN x.complex_id IS NOT NULL THEN N'공고 지번 = K-apt 지번 · 그 K-apt 의 단지 · 공고 뒤 준공'
                    ELSE N'공고 지번 = K-apt 지번 · 대장 없는 신축(K-apt) · 공고 뒤 사용승인' END, 0
          FROM silver.applyhome_pblanc p
          CROSS APPLY (SELECT kapt_code = MIN(k.kapt_code), n = COUNT(*) FROM silver.kapt_complex k WHERE k.is_current = 1 AND k.pnu = p.pnu) kk
          CROSS APPLY (SELECT k.kapt_code, k.kapt_usedate, complex_id = ck.complex_id, 준공 = c.oldest_use_apr, 세대 = c.hhld_cnt_sum, 활성 = c.is_active, 합침 = c.merged_into,
                              k세대 = COALESCE(NULLIF(k.hhld_cnt, 0), k.ho_cnt)
                         FROM silver.kapt_complex k
                         LEFT JOIN gold.complex_kapt ck ON ck.kapt_code = k.kapt_code
                         LEFT JOIN gold.complex c ON c.complex_id = ck.complex_id
                        WHERE k.is_current = 1 AND k.kapt_code = kk.kapt_code) x
         WHERE p.pnu IS NOT NULL AND kk.n = 1
           AND NOT EXISTS (SELECT 1 FROM gold.applyhome_link l WHERE l.house_manage_no = p.house_manage_no AND l.pblanc_no = p.pblanc_no)
           /* 공급 세대가 그 단지(K-apt) 세대보다 많으면 같은 단지가 아니다 — 롯데캐슬 이스트폴(631) 이 같은 지번의 어울채행복주택(300)에 붙던 것(첫 판에서 잡음) */
           AND (p.tot_suply IS NULL OR p.tot_suply <= COALESCE(x.세대, x.k세대, 2147483647))
           AND ((x.complex_id IS NOT NULL AND x.활성 = 1 AND x.합침 IS NULL AND x.세대 > 0 AND LEN(x.준공) = 8 AND x.준공 >= REPLACE(p.rcrit_pblanc_de, '-', ''))
             OR (x.complex_id IS NULL AND (NULLIF(x.kapt_usedate, '') IS NULL OR x.kapt_usedate >= REPLACE(p.rcrit_pblanc_de, '-', ''))));
        /* 2026-10-23 사장님 "1 ㄱㄱ"(11-225) 다섯째: **오피스텔 · 도시형생활주택 · 생활형숙박시설** 공고.
           오피스텔은 세대가 아니라 호로 세서 대장 세대가 0 이다 → 셋째 길(세대 단지)에 안 걸린다. 또 준공 뒤 남은 호를 다시 파는 공고가 많다.
           공고 지번 = 단지 필지 · 그 필지의 단지가 **하나** · 그 단지 사용승인 ≥ 공고일 − 3년 → 그 단지.
           막는 것(서울 실측 10건): 청량리동 235-4(1978) · 한강로3가 65-115(1985) · 오크우드(1999) 같은 **헐리기 전 옛 건물** · 3년 넘게 떨어진 것. 이름은 안 본다. */
        INSERT INTO gold.applyhome_link (house_manage_no, pblanc_no, complex_id, kapt_code, 근거, 거리m)
        SELECT p.house_manage_no, p.pblanc_no, MIN(c.complex_id),
               (SELECT TOP 1 ck.kapt_code FROM gold.complex_kapt ck WHERE ck.complex_id = MIN(c.complex_id)),
               N'오피스텔·도시형 · 공고 지번 = 단지 필지 · 필지 단지 1 · 공고 3년 전 이후 준공', 0
          FROM silver.applyhome_pblanc p
          JOIN gold.complex_pnu cp ON cp.pnu = p.pnu
          JOIN gold.complex c ON c.complex_id = cp.complex_id AND c.is_active = 1 AND c.merged_into IS NULL
         WHERE p.house_dtl_secd_nm IN (N'오피스텔', N'도시형생활주택', N'생활형숙박시설')
           AND NOT EXISTS (SELECT 1 FROM gold.applyhome_link l WHERE l.house_manage_no = p.house_manage_no AND l.pblanc_no = p.pblanc_no)
         GROUP BY p.house_manage_no, p.pblanc_no, p.rcrit_pblanc_de
        HAVING COUNT(DISTINCT c.complex_id) = 1
           AND MIN(CASE WHEN LEN(c.oldest_use_apr) = 8 THEN TRY_CONVERT(DATE, c.oldest_use_apr) END)
               >= DATEADD(YEAR, -3, TRY_CONVERT(DATE, REPLACE(p.rcrit_pblanc_de, '-', '')));
        /* 여섯째: **무순위 · 임의공급 · 불법행위 재공급** — 준공 뒤 남은 집 · 계약 취소분을 다시 파는 공고(신림스카이 17차 · 어반클라쎄목동 11차 …).
           공고 지번 = 단지 필지 · 그 필지의 **세대 단지가 하나** · 사용승인 ≥ 공고일 − 5년 · 세대 ≥ 공급 → 그 단지.
           막는 것(서울 실측 2건): 쌍문동 380-18(2008년 7세대) · 방배동 913-12(1978) — 헐리기 전 옛 건물. */
        INSERT INTO gold.applyhome_link (house_manage_no, pblanc_no, complex_id, kapt_code, 근거, 거리m)
        SELECT p.house_manage_no, p.pblanc_no, MIN(c.complex_id),
               (SELECT TOP 1 ck.kapt_code FROM gold.complex_kapt ck WHERE ck.complex_id = MIN(c.complex_id)),
               N'무순위·잔여 · 공고 지번 = 단지 필지 · 세대 단지 1 · 공고 5년 전 이후 준공 · 세대 ≥ 공급', 0
          FROM silver.applyhome_pblanc p
          JOIN gold.complex_pnu cp ON cp.pnu = p.pnu
          JOIN gold.complex c ON c.complex_id = cp.complex_id AND c.is_active = 1 AND c.merged_into IS NULL AND c.hhld_cnt_sum > 0
         WHERE p.house_secd_nm IN (N'무순위', N'임의공급', N'불법행위 재공급')
           AND NOT EXISTS (SELECT 1 FROM gold.applyhome_link l WHERE l.house_manage_no = p.house_manage_no AND l.pblanc_no = p.pblanc_no)
         GROUP BY p.house_manage_no, p.pblanc_no, p.rcrit_pblanc_de, p.tot_suply
        HAVING COUNT(DISTINCT c.complex_id) = 1
           AND MIN(CASE WHEN LEN(c.oldest_use_apr) = 8 THEN TRY_CONVERT(DATE, c.oldest_use_apr) END)
               >= DATEADD(YEAR, -5, TRY_CONVERT(DATE, REPLACE(p.rcrit_pblanc_de, '-', '')))
           AND (p.tot_suply IS NULL OR MIN(c.hhld_cnt_sum) >= p.tot_suply);
        /* 여덟째 (2026-10-24 16:53 사장님 "확실한거면 넣어", 11-264): **공고 지번이 지금 지적도에 없는 곳(사업 전 지번)** — 서울 정비계획을 다리로.
           ① 공고 지번 = 서울 정비계획(301)의 대표 지번(PNU 정확히 같음) ② 그 계획의 정비구역(redev_plan_link) 안에 필지가 절반 이상 든 단지
           ③ 그 단지 세대 = 정비계획 공급세대(정확히 같음) · 세대 ≥ 공고 공급 · 사용승인이 입주예정월 ±6개월 ④ 후보 하나.
           시험(16:31): 30건 · 이름 대조 30/30 같은 단지(남구로역 동일 센타시아 · 자양 하늘채 베르 …). 이름은 안 본다. */
        INSERT INTO gold.applyhome_link (house_manage_no, pblanc_no, complex_id, kapt_code, 근거, 거리m)
        SELECT p.house_manage_no, p.pblanc_no, MIN(c.complex_id),
               (SELECT TOP 1 ck.kapt_code FROM gold.complex_kapt ck WHERE ck.complex_id = MIN(c.complex_id)),
               N'사업 전 지번 = 정비계획 대표 지번 · 그 구역 단지 · 세대 = 계획 공급세대 · 입주월±6', 0
          FROM silver.applyhome_pblanc p
          JOIN silver.seoul_redev_plan r ON r.pnu = p.pnu
          JOIN gold.redev_plan_link rl ON rl.basic_info_seq = r.basic_info_seq
          JOIN gold.complex_redev_hit h ON h.present_sn = rl.present_sn AND h.xarea >= 0.5 * h.parea
          JOIN gold.complex c ON c.complex_id = h.complex_id AND c.is_active = 1 AND c.merged_into IS NULL
           AND c.hhld_cnt_sum = r.공급세대 AND c.hhld_cnt_sum >= ISNULL(p.tot_suply, 0) AND LEN(c.latest_use_apr) = 8
           AND ABS(DATEDIFF(MONTH, TRY_CONVERT(DATE, p.mvn_prearnge_ym + '01'), TRY_CONVERT(DATE, c.latest_use_apr))) <= 6
         WHERE p.pnu IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM silver.cadastral_parcel cp WHERE cp.pnu = p.pnu AND cp.is_current = 1)
           AND NOT EXISTS (SELECT 1 FROM gold.applyhome_link l WHERE l.house_manage_no = p.house_manage_no AND l.pblanc_no = p.pblanc_no)
         GROUP BY p.house_manage_no, p.pblanc_no HAVING COUNT(DISTINCT c.complex_id) = 1;
        /* 아홉째 (2026-10-24, 11-264): 사업 전 지번 · **본 공고(APT · 공공지원민간임대 · 도시형/오피스텔)이고 공급 30세대 이상** —
           같은 법정동 · 사용승인이 입주예정월 ±4개월 · **단지 세대 = 공고 공급세대(정확히 같음)** · 후보 하나.
           ★ '세대 ≥ 공급' 만으로는 틀린다(시험: DMC파인시티자이 → DMC SK VIEW · 관악센트씨엘 → 봉천 행복주택). 같은 수여야 한다.
           ★ 무순위 · 임의공급(4~12세대)은 같은 동 빌라에 우연히 같은 수가 있어 뺀다(리츠하우스 · 미라벨) — 그건 일곱째(형제)로 따라온다.
           시험: 12건 · 이름 대조 12/12(고덕강일 제일풍경채 · 상도 푸르지오 클라베뉴 · 안양리버자이르네 …). */
        INSERT INTO gold.applyhome_link (house_manage_no, pblanc_no, complex_id, kapt_code, 근거, 거리m)
        SELECT p.house_manage_no, p.pblanc_no, MIN(c.complex_id),
               (SELECT TOP 1 ck.kapt_code FROM gold.complex_kapt ck WHERE ck.complex_id = MIN(c.complex_id)),
               N'사업 전 지번 · 본 공고 · 같은 법정동 · 단지 세대 = 공급세대 · 입주월±4 · 후보 1', 0
          FROM silver.applyhome_pblanc p
          JOIN gold.complex c ON c.is_active = 1 AND c.merged_into IS NULL AND c.hhld_cnt_sum = p.tot_suply
           AND c.sigungu_cd + c.bjdong_cd = LEFT(p.pnu, 10) AND LEN(c.latest_use_apr) = 8
           AND ABS(DATEDIFF(MONTH, TRY_CONVERT(DATE, p.mvn_prearnge_ym + '01'), TRY_CONVERT(DATE, c.latest_use_apr))) <= 4
         WHERE p.pnu IS NOT NULL AND p.공고종류 IN ('APT', 'PBLPVT', 'URBTY') AND p.tot_suply >= 30
           AND NOT EXISTS (SELECT 1 FROM silver.cadastral_parcel cp WHERE cp.pnu = p.pnu AND cp.is_current = 1)
           AND NOT EXISTS (SELECT 1 FROM gold.applyhome_link l WHERE l.house_manage_no = p.house_manage_no AND l.pblanc_no = p.pblanc_no)
         GROUP BY p.house_manage_no, p.pblanc_no HAVING COUNT(DISTINCT c.complex_id) = 1;
        /* 일곱째 (2026-10-23 22:25 사장님 "이런 규칙이 괜찮아 보여", 11-249): **같은 공고 지번의 다른 공고가 이미 이어진 곳**.
           청약홈은 무순위·재공급·임의공급마다 관리번호를 새로 붙여, 본 분양은 이어졌는데 뒤 공고만 남는 일이 있다(강변역 센트럴 아이파크 2026.09 불법행위 재공급).
           ① 그 지번에서 이미 이어진 공고들이 가리키는 곳이 **하나**(단지 또는 대장 없는 K-apt)
           ② 그 필지에 그곳 말고 **다른 지금 단지 · K-apt 가 없음**(원베일리 조합원 취소분은 같은 필지 상가 단지가 있어 막힘)
           ③ 이 공고일 ≥ 이어진 공고 중 첫 공고일(먼저 나온 공고는 옛 사업일 수 있다 — 해링턴플레이스 노원 센트럴 본 공고는 막힘)
           ④ 공급 ≤ 그곳 세대.  이름은 안 본다. 위 여섯 길이 다 끝난 뒤 한 번만(이 길로 이은 것을 다시 형제로 쓰지 않는다).
           시험(993, 쓰기 전): 전국 20 중 17 이음(서울 10) · 막힘 3. */
        IF OBJECT_ID('tempdb..#형') IS NOT NULL DROP TABLE #형;
        SELECT q.pnu, 곳n = COUNT(DISTINCT COALESCE('C' + CAST(l.complex_id AS VARCHAR(12)), 'K' + l.kapt_code)),
               complex_id = MIN(l.complex_id), kapt_code = MIN(l.kapt_code), 첫 = MIN(REPLACE(q.rcrit_pblanc_de, '-', ''))
          INTO #형
          FROM gold.applyhome_link l JOIN silver.applyhome_pblanc q ON q.house_manage_no = l.house_manage_no AND q.pblanc_no = l.pblanc_no
         WHERE q.pnu IS NOT NULL
         GROUP BY q.pnu;
        IF OBJECT_ID('tempdb..#형후보') IS NOT NULL DROP TABLE #형후보;
        SELECT p.house_manage_no, p.pblanc_no, p.pnu, p.tot_suply, 공고 = REPLACE(p.rcrit_pblanc_de, '-', ''), h.곳n, h.complex_id, h.kapt_code, h.첫
          INTO #형후보
          FROM silver.applyhome_pblanc p JOIN #형 h ON h.pnu = p.pnu
         WHERE NOT EXISTS (SELECT 1 FROM gold.applyhome_link l WHERE l.house_manage_no = p.house_manage_no AND l.pblanc_no = p.pblanc_no);
        /* 집계 안에 서브쿼리를 넣지 않는다 — 다른 단지 · K-apt 수와 세대는 칸으로 먼저 */
        IF OBJECT_ID('tempdb..#형셈') IS NOT NULL DROP TABLE #형셈;
        SELECT u.house_manage_no, u.pblanc_no,
               다른단지 = (SELECT COUNT(DISTINCT cp.complex_id) FROM gold.complex_pnu cp JOIN gold.complex c ON c.complex_id = cp.complex_id
                           WHERE cp.pnu = u.pnu AND c.is_active = 1 AND c.merged_into IS NULL AND (u.complex_id IS NULL OR cp.complex_id <> u.complex_id)),
               다른kapt = (SELECT COUNT(*) FROM silver.kapt_complex k WHERE k.is_current = 1 AND k.pnu = u.pnu AND (u.kapt_code IS NULL OR k.kapt_code <> u.kapt_code)
                           AND NOT EXISTS (SELECT 1 FROM gold.complex_kapt ck WHERE ck.kapt_code = k.kapt_code AND ck.complex_id = u.complex_id)),
               세대 = COALESCE((SELECT c.hhld_cnt_sum FROM gold.complex c WHERE c.complex_id = u.complex_id),
                               (SELECT TOP 1 COALESCE(NULLIF(k.hhld_cnt, 0), k.ho_cnt) FROM silver.kapt_complex k WHERE k.is_current = 1 AND k.kapt_code = u.kapt_code))
          INTO #형셈 FROM #형후보 u;
        INSERT INTO gold.applyhome_link (house_manage_no, pblanc_no, complex_id, kapt_code, 근거, 거리m)
        SELECT u.house_manage_no, u.pblanc_no, u.complex_id, u.kapt_code,
               N'같은 공고 지번의 다른 공고가 이어진 곳 · 그 필지에 다른 단지 없음 · 첫 공고 이후 · 세대 ≥ 공급', 0
          FROM #형후보 u JOIN #형셈 o ON o.house_manage_no = u.house_manage_no AND o.pblanc_no = u.pblanc_no
         WHERE u.곳n = 1 AND o.다른단지 = 0 AND o.다른kapt = 0 AND u.공고 >= u.첫
           AND (u.tot_suply IS NULL OR u.tot_suply <= ISNULL(o.세대, 2147483647));
    COMMIT;

    SELECT 공고 = (SELECT COUNT(*) FROM silver.applyhome_pblanc),
           법정동 = (SELECT COUNT(*) FROM silver.applyhome_pblanc WHERE lawd_cd IS NOT NULL),
           필지 = (SELECT COUNT(*) FROM #p WHERE plat IS NOT NULL),
           이음 = (SELECT COUNT(*) FROM gold.applyhome_link),
           단지에 = (SELECT COUNT(*) FROM gold.applyhome_link WHERE complex_id IS NOT NULL),
           신축에 = (SELECT COUNT(*) FROM gold.applyhome_link WHERE complex_id IS NULL AND kapt_code IS NOT NULL),
           오피스텔길 = (SELECT COUNT(*) FROM gold.applyhome_link WHERE 근거 LIKE N'오피스텔·도시형%'),
           무순위길 = (SELECT COUNT(*) FROM gold.applyhome_link WHERE 근거 LIKE N'무순위·잔여%'),
           형제길 = (SELECT COUNT(*) FROM gold.applyhome_link WHERE 근거 LIKE N'같은 공고 지번의 다른 공고%'),
           정비계획길 = (SELECT COUNT(*) FROM gold.applyhome_link WHERE 근거 LIKE N'사업 전 지번 = 정비계획%'),
           세대같음길 = (SELECT COUNT(*) FROM gold.applyhome_link WHERE 근거 LIKE N'사업 전 지번 · 본 공고%');
END
GO
