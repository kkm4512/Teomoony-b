/* ============================================================
   301_seoul_redev_plan : 서울플랜+ 정비사업 계획 — 계획 용적률·건폐율·층수·높이·공급세대 (2026-10-22, 사장님 "찾아봐")
   ★ 출처: 서울 열린데이터광장 Open API (키 = .env SEOUL_OPENAPI_KEY)
       vnBsnsNmtn      정비사업 현황(OA-23112)         830
       vnBsnsRrgnPrmt  재정비촉진사업 현황(OA-23114)    280
       vnBsnsSmalNmtn  소규모정비사업 현황(OA-23113)  1,024
   ★ 원문 0 은 **'안 적음'** 이다(공급 659세대인 사업이 용적률 0.0) → 숫자 칸은 0 이면 NULL. 원문은 raw_json.
   ★ 구역 경계(silver.redev_zone, OA-22712)와 잇는 번호가 **없다**(BASIC_INFO_SEQ ≠ present_sn).
     이름으로 잇지 않는다(정책 1장). 잇는 길 = **사업 위치 지번**("공릉동 254 일대") → PNU → 그 필지가 들어간 구역
     + **사업 면적이 구역 면적과 5% 안**. 둘 다 맞고 후보가 하나일 때만 잇는다(gold.redev_plan_link · 근거).
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
IF OBJECT_ID('silver.seoul_redev_plan') IS NULL
CREATE TABLE silver.seoul_redev_plan (
    basic_info_seq   BIGINT         NOT NULL CONSTRAINT pk_seoul_redev_plan PRIMARY KEY,
    자료             VARCHAR(10)    NOT NULL,      -- NMTN 정비 · RRGN 재정비촉진 · SMAL 소규모
    대분류코드       VARCHAR(10)    NULL,
    대분류           NVARCHAR(60)   NULL,
    소분류코드       VARCHAR(10)    NULL,
    소분류           NVARCHAR(60)   NULL,
    sgg_cd           CHAR(5)        NULL,
    사업명           NVARCHAR(300)  NULL,
    위치             NVARCHAR(300)  NULL,
    사업면적         DECIMAL(14,2)  NULL,
    용도지역_전      NVARCHAR(300)  NULL,
    용도지역_후      NVARCHAR(300)  NULL,
    권역             NVARCHAR(40)   NULL,
    추진단계코드     VARCHAR(10)    NULL,
    추진단계         NVARCHAR(60)   NULL,
    추진일           CHAR(10)       NULL,
    지정일           CHAR(10)       NULL,
    지구명           NVARCHAR(200)  NULL,
    연면적           DECIMAL(16,2)  NULL,
    용적률           DECIMAL(8,2)   NULL,
    건폐율           DECIMAL(8,2)   NULL,
    층수             NVARCHAR(40)   NULL,          -- '2/33' = 지하/지상(원문)
    높이m            DECIMAL(8,2)   NULL,
    용도             NVARCHAR(200)  NULL,
    공급세대         INT            NULL,
    분양세대         INT            NULL,
    임대세대         INT            NULL,
    임대비율         DECIMAL(6,2)   NULL,
    홈페이지         NVARCHAR(400)  NULL,
    위치_동          NVARCHAR(40)   NULL,
    위치_산          CHAR(1)        NULL,
    위치_본번        VARCHAR(10)    NULL,
    위치_부번        VARCHAR(10)    NULL,
    lawd_cd          CHAR(10)       NULL,
    pnu              CHAR(19)       NULL,
    raw_json         NVARCHAR(MAX)  NULL,
    loaded_at        DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME()
);
GO
IF OBJECT_ID('gold.redev_plan_link') IS NULL
CREATE TABLE gold.redev_plan_link (
    basic_info_seq   BIGINT         NOT NULL CONSTRAINT pk_redev_plan_link PRIMARY KEY,
    present_sn       VARCHAR(40)    NOT NULL,
    근거             NVARCHAR(200)  NOT NULL,
    면적차pct        DECIMAL(6,2)   NULL,
    굳힌시각         DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME()
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_redev_plan_link_sn')
    CREATE INDEX ix_redev_plan_link_sn ON gold.redev_plan_link (present_sn);
GO
IF OBJECT_ID('ops.redev_plan_mismatch') IS NULL
CREATE TABLE ops.redev_plan_mismatch (
    basic_info_seq   BIGINT        NOT NULL CONSTRAINT pk_redev_plan_mismatch PRIMARY KEY,
    코드구역         VARCHAR(40)   NOT NULL,     -- 자치구·소분류·면적이 가리킨 구역
    지번구역         VARCHAR(40)   NOT NULL,     -- 위치 지번이 가리킨 구역
    기록시각         DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);
GO
CREATE OR ALTER PROCEDURE gold.usp_link_redev_plan
AS
BEGIN
    SET NOCOUNT ON;
    /* ① 위치 조각 → 법정동(시군구 + 동, 후보 1) → PNU(한 자리에서만 만든다) */
    UPDATE p SET lawd_cd = l.cd
      FROM silver.seoul_redev_plan p
     CROSS APPLY (SELECT cd = MIN(lc.lawd_cd), n = COUNT(*) FROM meta.lawd_code lc
                   WHERE lc.ri_nm IS NULL AND lc.is_abolished = 0 AND LEFT(lc.lawd_cd, 5) = p.sgg_cd AND lc.emd_nm = p.위치_동) l
     WHERE p.위치_동 IS NOT NULL AND l.n = 1;
    UPDATE p SET pnu = meta.fn_make_pnu(LEFT(p.lawd_cd, 5), RIGHT(p.lawd_cd, 5), ISNULL(p.위치_산, '0'), p.위치_본번, ISNULL(p.위치_부번, '0'))
      FROM silver.seoul_redev_plan p WHERE p.lawd_cd IS NOT NULL AND p.위치_본번 IS NOT NULL;

    /* ② 그 필지가 들어간 구역 중 면적이 5% 안인 것 */
    IF OBJECT_ID('tempdb..#rc') IS NOT NULL DROP TABLE #rc;
    SELECT p.basic_info_seq, z.present_sn,
           차 = CAST(100.0 * ABS(z.area_m2 - p.사업면적) / NULLIF(z.area_m2, 0) AS DECIMAL(8,2))
      INTO #rc
      FROM silver.seoul_redev_plan p
      JOIN silver.cadastral_parcel cp ON cp.pnu = p.pnu AND cp.is_current = 1 AND cp.geom IS NOT NULL
      JOIN silver.redev_zone z ON z.is_current = 1 AND z.geom IS NOT NULL
       AND z.bbox_minx <= cp.bbox_maxx AND z.bbox_maxx >= cp.bbox_minx AND z.bbox_miny <= cp.bbox_maxy AND z.bbox_maxy >= cp.bbox_miny
       AND z.geom.STIntersects(cp.geom) = 1
     WHERE p.사업면적 > 0;
    /* ② -2 (2026-10-22): '신길동 190' 처럼 부번 없이 적은 위치는 190-0 필지가 없을 때가 많다(190-1 · 190-23 … 만 있다).
       그 필지를 못 찾은 계획만, **본번이 같은 필지**(PNU 앞 15자리 = 법정동 + 산 + 본번) 중 구역 안에 있는 것으로 찾는다. 면적 5% 조건은 같다. */
    INSERT INTO #rc (basic_info_seq, present_sn, 차)
    SELECT DISTINCT p.basic_info_seq, z.present_sn,
           CAST(100.0 * ABS(z.area_m2 - p.사업면적) / NULLIF(z.area_m2, 0) AS DECIMAL(8,2))
      FROM silver.seoul_redev_plan p
      JOIN silver.cadastral_parcel cp ON cp.pnu LIKE LEFT(p.pnu, 15) + '%' AND cp.is_current = 1 AND cp.geom IS NOT NULL
      JOIN silver.redev_zone z ON z.is_current = 1 AND z.geom IS NOT NULL
       AND z.bbox_minx <= cp.bbox_maxx AND z.bbox_maxx >= cp.bbox_minx AND z.bbox_miny <= cp.bbox_maxy AND z.bbox_maxy >= cp.bbox_miny
       AND z.geom.STIntersects(cp.geom) = 1
     WHERE p.사업면적 > 0 AND p.pnu IS NOT NULL AND ISNULL(p.위치_부번, '0') = '0'
       AND NOT EXISTS (SELECT 1 FROM silver.cadastral_parcel c0 WHERE c0.pnu = p.pnu AND c0.is_current = 1);
    DELETE FROM #rc WHERE 차 IS NULL OR 차 > 5;

    /* ③ (2026-10-22 사장님 "굳 ㄱㄱ") **주 연결 = 코드 조합 키** — 두 자료 모두 서울플랜+ 체계의 코드를 쓴다:
         자치구 코드(signgu_se = SITE_CODE) + 사업 소분류 코드(sclas_cl = CLASSIFY_L) + 면적(소수점까지 같음, DGM_AR = BSNS_AREA).
       셋 다 같고 후보가 하나일 때만. 지번(②)은 **확인용** — 둘이 다른 구역을 가리키면 잇지 않고 ops.redev_plan_mismatch 에 남긴다. */
    IF OBJECT_ID('tempdb..#kc') IS NOT NULL DROP TABLE #kc;
    SELECT p.basic_info_seq, present_sn = MIN(z.present_sn)
      INTO #kc
      FROM silver.seoul_redev_plan p
      JOIN silver.redev_zone z ON z.is_current = 1 AND z.signgu_se = p.sgg_cd AND z.sclas_cl = p.소분류코드 AND z.area_m2 = p.사업면적
     WHERE p.사업면적 > 0
     GROUP BY p.basic_info_seq HAVING COUNT(DISTINCT z.present_sn) = 1;
    IF OBJECT_ID('tempdb..#ac') IS NOT NULL DROP TABLE #ac;
    SELECT basic_info_seq, present_sn = MIN(present_sn), 차 = MIN(차)
      INTO #ac FROM #rc GROUP BY basic_info_seq HAVING COUNT(DISTINCT present_sn) = 1;

    BEGIN TRAN;
        DELETE FROM gold.redev_plan_link;
        DELETE FROM ops.redev_plan_mismatch;
        /* 코드도 맞고 지번도 같은 구역 */
        INSERT INTO gold.redev_plan_link (basic_info_seq, present_sn, 근거, 면적차pct)
        SELECT k.basic_info_seq, k.present_sn, N'코드 일치(자치구·소분류·면적) · 위치 지번도 같은 구역', 0
          FROM #kc k JOIN #ac a ON a.basic_info_seq = k.basic_info_seq AND a.present_sn = k.present_sn;
        /* 코드는 맞고 지번은 못 봄(지번을 못 풀었거나 필지가 없음) */
        INSERT INTO gold.redev_plan_link (basic_info_seq, present_sn, 근거, 면적차pct)
        SELECT k.basic_info_seq, k.present_sn, N'코드 일치(자치구·소분류·면적) — 위치 지번으로는 확인 못 함', 0
          FROM #kc k WHERE NOT EXISTS (SELECT 1 FROM #ac a WHERE a.basic_info_seq = k.basic_info_seq);
        /* 둘이 다른 구역 → 잇지 않고 남긴다 */
        INSERT INTO ops.redev_plan_mismatch (basic_info_seq, 코드구역, 지번구역)
        SELECT k.basic_info_seq, k.present_sn, a.present_sn
          FROM #kc k JOIN #ac a ON a.basic_info_seq = k.basic_info_seq AND a.present_sn <> k.present_sn;
        /* 코드로는 못 찾고 지번 + 면적 5% 로만 찾은 것 */
        INSERT INTO gold.redev_plan_link (basic_info_seq, present_sn, 근거, 면적차pct)
        SELECT a.basic_info_seq, a.present_sn, N'위치 지번이 구역 안 · 면적 5% 안(코드는 안 맞음)', a.차
          FROM #ac a WHERE NOT EXISTS (SELECT 1 FROM #kc k WHERE k.basic_info_seq = a.basic_info_seq);
        /* 한 구역에 계획이 둘 이상 붙으면 둘 다 뺀다 — 어느 쪽이 그 구역의 계획인지 모른다 */
        DELETE l FROM gold.redev_plan_link l
         WHERE l.present_sn IN (SELECT present_sn FROM gold.redev_plan_link GROUP BY present_sn HAVING COUNT(*) > 1);
    COMMIT;

    SELECT 계획 = (SELECT COUNT(*) FROM silver.seoul_redev_plan),
           법정동 = (SELECT COUNT(*) FROM silver.seoul_redev_plan WHERE lawd_cd IS NOT NULL),
           필지 = (SELECT COUNT(*) FROM silver.seoul_redev_plan p WHERE EXISTS (SELECT 1 FROM silver.cadastral_parcel cp WHERE cp.pnu = p.pnu AND cp.is_current = 1)),
           후보있음 = (SELECT COUNT(DISTINCT basic_info_seq) FROM #rc),
           이음 = (SELECT COUNT(*) FROM gold.redev_plan_link),
           코드지번둘다 = (SELECT COUNT(*) FROM gold.redev_plan_link WHERE 근거 LIKE N'코드 일치%같은 구역'),
           코드만 = (SELECT COUNT(*) FROM gold.redev_plan_link WHERE 근거 LIKE N'코드 일치%확인 못 함'),
           지번만 = (SELECT COUNT(*) FROM gold.redev_plan_link WHERE 근거 LIKE N'위치 지번%'),
           어긋남 = (SELECT COUNT(*) FROM ops.redev_plan_mismatch);
END
GO
