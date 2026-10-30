/* 389 가단지코드 — 대장 전 건물(공사 중 387 · 사업승인 384)에 단지 번호를 붙인다 (2026-10-30 사장님 "가단지코드를 붙이는 건 어때?" · "ㄱㄱ")
   ★ 왜: 단지 번호로 받는 칸(이 땅의 역사 · 토지이용계획 · 옛 대장 · 병원 · 약국 · 어린이집 · 주변 점 · 공유 주소 /c/번호 · 관심 · 최근 본 단지)이
     대장 전 건물에서도 그대로 돌게. 일반 단지 표(gold.complex)에는 **넣지 않는다** — 단지 수 · 마커 · 통계 · AI 검색에 허가 건물이 섞이지 않게.
   ★ 번호: 9억번대(900,000,001 ~) — 일반 단지 번호와 겹치지 않는다. 한 번 준 번호는 다시 쓰지 않는다(이 표는 기록 — 지우지 않는다).
   ★ 10-30 22:32 사장님 "건축대장에는 없지만 분양 · 청약 · 건축인허가 데이터로 단지처럼" · "ㄱㄱ" — 셋째 원천 **청약 공고(종류 a)**:
     단지에 안 이어진 청약홈 공고 묶음(같은 공고 지번 · 지번이 없으면 같은 공급 위치 글자) 가운데
       · 같은 지번에 가단지(p · h)가 없고 · 같은 지번에 공고일 이후 사용승인된 대장이 없고
       · 묶음 첫 공고의 입주 예정월이 공고월보다 뒤(공고 때 이미 입주한 분양전환 · 잔여세대는 다 지은 단지라 뺀다)
       · 처음 붙일 때 첫 공고의 입주 예정월이 이번 달 이후(나중 공가 · 잔여 재공급 공고의 입주월로 판정하지 않는다)(입주가 지난 공고는 대개 다 지은 단지 — 대장과 못 이은 것이라 가단지를 만들지 않는다)
     → 한 번 붙으면 대장 · p/h · 단지 연결이 생길 때까지 남는다(1년 넘어도 빼지 않는다 — 사장님 10-30).
     지번이 없으면(택지 블록) 좌표 NULL — 검색 · 목록으로만. 공고 → 가단지는 gold.pre_applyhome(파생 · 매번 다시).
   ★ 상태: 살아있음(지금 핀 · 원문에 있음) · 이동(같은 필지에 사용승인일 ≥ 허가 · 승인일인 대장 단지가 생김 → 그 단지 번호로 옮겨 감) · 없어짐(원문에서 빠짐 · 옮길 단지 없음).
     이름으로 잇지 않는다. 이동한 번호로 들어오면 화면이 정식 단지로 넘어간다(묶인 옛 코드와 같은 장치). */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
IF OBJECT_ID('gold.seq_pre_complex') IS NULL
    CREATE SEQUENCE gold.seq_pre_complex AS INT START WITH 900000001 INCREMENT BY 1 NO CYCLE;
GO
IF OBJECT_ID('gold.pre_complex') IS NULL
CREATE TABLE gold.pre_complex (
    complex_id      INT           NOT NULL CONSTRAINT pk_pre_complex PRIMARY KEY CONSTRAINT df_pre_complex_id DEFAULT (NEXT VALUE FOR gold.seq_pre_complex),
    종류            CHAR(1)       NOT NULL,          -- p 공사 중(건축허가) · h 사업승인(주택인허가) · a 청약 공고(청약홈 · 10-30)
    원문pk          VARCHAR(50)   NOT NULL,          -- 관리_허가대장_PK · 관리_주택대장_PK
    pnu             CHAR(19)      NULL,
    이름            NVARCHAR(200) NULL,
    lat             FLOAT         NULL,
    lng             FLOAT         NULL,
    기준일          CHAR(8)       NULL,              -- 허가일 · 사업계획승인일 — 이동 판정의 기준
    상태            NVARCHAR(10)  NOT NULL CONSTRAINT df_pre_complex_st DEFAULT (N'살아있음'),
    이동_complex_id INT           NULL,
    처음때          DATETIME2(0)  NOT NULL CONSTRAINT df_pre_complex_t0 DEFAULT (SYSDATETIME()),
    바뀐때          DATETIME2(0)  NOT NULL CONSTRAINT df_pre_complex_t1 DEFAULT (SYSDATETIME()),
    CONSTRAINT uq_pre_complex UNIQUE (종류, 원문pk)
);
GO
CREATE OR ALTER PROCEDURE gold.usp_refresh_pre_complex
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF OBJECT_ID('tempdb..#now') IS NOT NULL DROP TABLE #now;
    CREATE TABLE #now (종류 CHAR(1) NOT NULL, 원문pk VARCHAR(50) NOT NULL, pnu CHAR(19) NULL, 이름 NVARCHAR(200) NULL, lat FLOAT NULL, lng FLOAT NULL, 기준일 CHAR(8) NULL,
                       PRIMARY KEY (종류, 원문pk));
    IF OBJECT_ID('gold.pre_build') IS NOT NULL
        INSERT #now SELECT 'p', pk, pnu, 이름, lat, lng, 허가일 FROM gold.pre_build;
    IF OBJECT_ID('gold.house_plan') IS NOT NULL
        INSERT #now SELECT 'h', hp_pk, pnu, 이름, lat, lng, 승인일 FROM gold.house_plan WHERE 상태 <> N'완공 대장 있음';

    /* 청약 공고(a) — 단지에 안 이어진 공고를 묶는다: 공고 지번(pnu)이 있으면 지번, 없으면 공급 위치 글자(띄어쓰기 뺌). 이름으로 묶지 않는다. */
    IF OBJECT_ID('tempdb..#ah') IS NOT NULL DROP TABLE #ah;
    SELECT p.house_manage_no, p.pblanc_no, p.pnu, p.house_nm, p.공고종류, p.mvn_prearnge_ym,
           공고일 = LEFT(REPLACE(REPLACE(LTRIM(RTRIM(p.rcrit_pblanc_de)), '-', ''), ' ', ''), 8),
           g = CAST(COALESCE('P' + p.pnu, 'A' + NULLIF(REPLACE(REPLACE(LTRIM(RTRIM(p.hssply_adres)), ' ', ''), NCHAR(160), ''), '')) AS NVARCHAR(320))
      INTO #ah
      FROM silver.applyhome_pblanc p
     WHERE NOT EXISTS (SELECT 1 FROM gold.applyhome_link l WHERE l.house_manage_no = p.house_manage_no AND l.complex_id IS NOT NULL);
    DELETE #ah WHERE g IS NULL;
    IF OBJECT_ID('tempdb..#ag') IS NOT NULL DROP TABLE #ag;
    SELECT g, pnu = MAX(pnu), 원문pk = MIN(house_manage_no), 입주 = MAX(mvn_prearnge_ym), 기준일 = MIN(공고일) INTO #ag FROM #ah GROUP BY g;
    /* 첫 공고의 입주 예정월 — 묶음의 처음 분양이 언제 입주하나(나중 공고는 공가 · 잔여 재공급일 수 있다) */
    ALTER TABLE #ag ADD 입주0 CHAR(6) NULL;
    UPDATE g SET 입주0 = (SELECT TOP 1 a.mvn_prearnge_ym FROM #ah a WHERE a.g = g.g AND a.mvn_prearnge_ym IS NOT NULL ORDER BY a.공고일, a.house_manage_no, a.pblanc_no) FROM #ag g;
    DECLARE @이번달 CHAR(6) = CONVERT(CHAR(6), SYSDATETIME(), 112);
    INSERT #now (종류, 원문pk, pnu, 이름, lat, lng, 기준일)
    SELECT 'a', g.원문pk, g.pnu, gold.fn_name_mask(nm.house_nm), CAST(cp.centroid_lat AS FLOAT), CAST(cp.centroid_lng AS FLOAT), g.기준일
      FROM #ag g
      OUTER APPLY (SELECT TOP 1 a.house_nm FROM #ah a WHERE a.g = g.g
                    ORDER BY CASE a.공고종류 WHEN 'APT' THEN 0 WHEN 'URBTY' THEN 1 WHEN 'PBLPVT' THEN 2 ELSE 3 END, a.공고일, a.house_manage_no) nm
      OUTER APPLY (SELECT TOP 1 c.centroid_lat, c.centroid_lng FROM silver.cadastral_parcel c WHERE c.pnu = g.pnu AND c.is_current = 1) cp
     WHERE g.g = (SELECT MIN(g2.g) FROM #ag g2 WHERE g2.원문pk = g.원문pk)   -- 한 관리번호가 두 묶음에 걸치면 하나만(번호 겹침 방지)
       AND g.입주0 > LEFT(g.기준일, 6)   -- 첫 공고 때 이미 입주한 것(분양전환 · 잔여세대 · 임대 재공급)은 다 지은 단지 — 대장과 못 이은 것이라 가단지로 만들지 않는다
       /* 첫 공고의 입주가 이번 달 이후이거나, 붙일 때(처음때) 입주 전이었던 a 는 대장이 생길 때까지 남긴다 */
       AND (g.입주0 >= @이번달 OR EXISTS (SELECT 1 FROM gold.pre_complex x WHERE x.종류 = 'a' AND x.원문pk = g.원문pk AND x.상태 = N'살아있음'
                                            AND g.입주0 >= CONVERT(CHAR(6), x.처음때, 112)))
       AND NOT (g.pnu IS NOT NULL AND EXISTS (SELECT 1 FROM #now n WHERE n.pnu = g.pnu AND n.종류 IN ('p', 'h')))
       AND NOT (g.pnu IS NOT NULL AND EXISTS (SELECT 1 FROM silver.bld_title t WHERE t.pnu = g.pnu AND t.is_current = 1 AND t.use_apr_day >= g.기준일));

    BEGIN TRAN;
    /* 새로 생긴 것 — 번호를 준다 */
    INSERT gold.pre_complex (종류, 원문pk, pnu, 이름, lat, lng, 기준일)
    SELECT n.종류, n.원문pk, n.pnu, n.이름, n.lat, n.lng, n.기준일
      FROM #now n WHERE NOT EXISTS (SELECT 1 FROM gold.pre_complex p WHERE p.종류 = n.종류 AND p.원문pk = n.원문pk);
    /* 지금도 있는 것 — 값 맞추고 살아있음(빠졌다 돌아온 것 포함) */
    UPDATE p SET pnu = n.pnu, 이름 = n.이름, lat = n.lat, lng = n.lng, 기준일 = n.기준일, 상태 = N'살아있음', 이동_complex_id = NULL, 바뀐때 = SYSDATETIME()
      FROM gold.pre_complex p JOIN #now n ON n.종류 = p.종류 AND n.원문pk = p.원문pk
     WHERE p.상태 <> N'살아있음' OR ISNULL(p.pnu, '') <> ISNULL(n.pnu, '') OR ISNULL(p.이름, N'') <> ISNULL(n.이름, N'')
        OR ISNULL(p.lat, 0) <> ISNULL(n.lat, 0) OR ISNULL(p.lng, 0) <> ISNULL(n.lng, 0) OR ISNULL(p.기준일, '') <> ISNULL(n.기준일, '');
    /* 빠진 것 — 같은 필지에 기준일 이후 사용승인된 대장 단지가 있으면 그리로 옮겨 감, 없으면 없어짐 */
    UPDATE p SET 이동_complex_id = COALESCE(t.complex_id, l.complex_id, s.complex_id),
                 상태 = CASE WHEN COALESCE(t.complex_id, l.complex_id, s.complex_id) IS NOT NULL THEN N'이동' ELSE N'없어짐' END, 바뀐때 = SYSDATETIME()
      FROM gold.pre_complex p
      OUTER APPLY (SELECT TOP 1 cb.complex_id
                     FROM silver.bld_title b
                     JOIN gold.complex_bld cb ON cb.mgm_bldrgst_pk = b.mgm_bldrgst_pk
                     JOIN gold.complex c ON c.complex_id = cb.complex_id AND c.is_active = 1
                    WHERE b.pnu = p.pnu AND b.is_current = 1 AND b.use_apr_day >= p.기준일
                    ORDER BY b.use_apr_day DESC, cb.complex_id) t
      /* a(청약 공고): 그 공고가 단지에 이어졌으면 그 단지로 */
      OUTER APPLY (SELECT TOP 1 l.complex_id FROM gold.applyhome_link l
                    WHERE p.종류 = 'a' AND l.house_manage_no = p.원문pk AND l.complex_id IS NOT NULL ORDER BY l.complex_id) l
      /* a: 같은 지번에 사업승인 · 공사 중 가단지가 생겼으면 그리로(같은 사업을 두 번 보이지 않게) */
      OUTER APPLY (SELECT TOP 1 x.complex_id FROM gold.pre_complex x
                    WHERE p.종류 = 'a' AND p.pnu IS NOT NULL AND x.pnu = p.pnu AND x.종류 IN ('h', 'p') AND x.상태 = N'살아있음'
                    ORDER BY CASE x.종류 WHEN 'h' THEN 0 ELSE 1 END, x.complex_id) s
     WHERE p.상태 = N'살아있음' AND NOT EXISTS (SELECT 1 FROM #now n WHERE n.종류 = p.종류 AND n.원문pk = p.원문pk);

    /* 공고 → 가단지(파생 · 매번 다시) — 단지에 안 이어진 공고가 어느 가단지에 속하나. 같은 지번이면 h → p → a 순, 지번 없으면 같은 묶음의 a */
    IF OBJECT_ID('gold.pre_applyhome_n') IS NOT NULL DROP TABLE gold.pre_applyhome_n;
    SELECT a.house_manage_no, a.pblanc_no, complex_id = COALESCE(s.complex_id, w.complex_id)
      INTO gold.pre_applyhome_n
      FROM #ah a
      OUTER APPLY (SELECT TOP 1 x.complex_id FROM gold.pre_complex x
                    WHERE a.pnu IS NOT NULL AND x.pnu = a.pnu AND x.상태 = N'살아있음'
                    ORDER BY CASE x.종류 WHEN 'h' THEN 0 WHEN 'p' THEN 1 ELSE 2 END, x.complex_id) s
      OUTER APPLY (SELECT TOP 1 x.complex_id FROM #ag g JOIN gold.pre_complex x ON x.종류 = 'a' AND x.원문pk = g.원문pk AND x.상태 = N'살아있음'
                    WHERE a.pnu IS NULL AND g.g = a.g) w
     WHERE COALESCE(s.complex_id, w.complex_id) IS NOT NULL;
    CREATE UNIQUE CLUSTERED INDEX cx_pre_applyhome ON gold.pre_applyhome_n (house_manage_no, pblanc_no);
    CREATE INDEX ix_pre_applyhome_cid ON gold.pre_applyhome_n (complex_id);
    IF OBJECT_ID('gold.pre_applyhome') IS NOT NULL DROP TABLE gold.pre_applyhome;
    EXEC sp_rename 'gold.pre_applyhome_n', 'pre_applyhome';
    COMMIT;
    SELECT x = (SELECT STRING_AGG(CONCAT(상태, ' ', 종류, ' ', n), ' · ') FROM (SELECT 상태, 종류, n = COUNT(*) FROM gold.pre_complex GROUP BY 상태, 종류) z),
           공고이음 = (SELECT COUNT(*) FROM gold.pre_applyhome), 공고가단지 = (SELECT COUNT(DISTINCT complex_id) FROM gold.pre_applyhome);
END
GO
EXEC gold.usp_refresh_pre_complex;
GO
/* 가단지 요청 동안 바꿔 끼울 것(db.js 가단지바꿈) — 이름 자리에 그대로 들어가게 함수 · 뷰로(별칭이 있든 없든 문법이 맞게) */
CREATE OR ALTER FUNCTION gold.fn_pnu_permit (@pnu CHAR(19), @cid INT) RETURNS TABLE AS RETURN
SELECT complex_id = @cid, a.mgm_pmsrgst_pk, match_by = CAST('PNU' AS VARCHAR(10))
  FROM silver.arch_permit a WHERE a.pnu = @pnu AND a.is_current = 1;
GO
CREATE OR ALTER FUNCTION gold.fn_pnu_redev_hit (@pnu CHAR(19), @cid INT) RETURNS TABLE AS RETURN
SELECT complex_id = @cid, present_sn, xarea = SUM(xarea), parea = SUM(parea)
  FROM gold.fn_pnu_redev(@pnu, @cid) GROUP BY present_sn;
GO
CREATE OR ALTER VIEW gold.v_empty_applyhome_link AS SELECT TOP 0 * FROM gold.applyhome_link;
GO
CREATE OR ALTER VIEW gold.v_empty_complex_ho AS SELECT TOP 0 * FROM gold.v_complex_ho;
GO
