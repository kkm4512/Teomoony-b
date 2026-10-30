/* 389 가단지코드 — 대장 전 건물(공사 중 387 · 사업승인 384)에 단지 번호를 붙인다 (2026-10-30 사장님 "가단지코드를 붙이는 건 어때?" · "ㄱㄱ")
   ★ 왜: 단지 번호로 받는 칸(이 땅의 역사 · 토지이용계획 · 옛 대장 · 병원 · 약국 · 어린이집 · 주변 점 · 공유 주소 /c/번호 · 관심 · 최근 본 단지)이
     대장 전 건물에서도 그대로 돌게. 일반 단지 표(gold.complex)에는 **넣지 않는다** — 단지 수 · 마커 · 통계 · AI 검색에 허가 건물이 섞이지 않게.
   ★ 번호: 9억번대(900,000,001 ~) — 일반 단지 번호와 겹치지 않는다. 한 번 준 번호는 다시 쓰지 않는다(이 표는 기록 — 지우지 않는다).
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
    종류            CHAR(1)       NOT NULL,          -- p 공사 중(건축허가) · h 사업승인(주택인허가)
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
    UPDATE p SET 이동_complex_id = t.complex_id, 상태 = CASE WHEN t.complex_id IS NOT NULL THEN N'이동' ELSE N'없어짐' END, 바뀐때 = SYSDATETIME()
      FROM gold.pre_complex p
      OUTER APPLY (SELECT TOP 1 cb.complex_id
                     FROM silver.bld_title b
                     JOIN gold.complex_bld cb ON cb.mgm_bldrgst_pk = b.mgm_bldrgst_pk
                     JOIN gold.complex c ON c.complex_id = cb.complex_id AND c.is_active = 1
                    WHERE b.pnu = p.pnu AND b.is_current = 1 AND b.use_apr_day >= p.기준일
                    ORDER BY b.use_apr_day DESC, cb.complex_id) t
     WHERE p.상태 = N'살아있음' AND NOT EXISTS (SELECT 1 FROM #now n WHERE n.종류 = p.종류 AND n.원문pk = p.원문pk);
    COMMIT;
    SELECT 상태, 종류, n = COUNT(*), 최소 = MIN(complex_id), 최대 = MAX(complex_id) FROM gold.pre_complex GROUP BY 상태, 종류 ORDER BY 1, 2;
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
