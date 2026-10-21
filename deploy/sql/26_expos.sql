SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* ============================================================
   26_expos : 전유부 (호 단위) — 2026-10-16

   ★ 정책.md 4장이 기각한 것은 **전유공용면적**(getBrExposPubuseAreaInfo)이다.
     사유는 "호당 전유 1행 + 공용 N행 -> 응답의 80%가 공용, 지번당 수천 건".
     실측으로 확인됨 (돈암동 636번지):

        전유부          1,102      호당 1행
        전유공용면적     7,658      6.9배 — 기각 사유 그대로

     **전유부는 그 사유에 해당하지 않는다.** 기각된 축이 아니라 검토된 적 없는 축이다.

   ★ 동 연결은 **코드로 떨어진다. 이름 매칭이 없다.**

        전유부.mgm_bldrgst_pk
          = 기본개요(regstr_kind_cd=4).mgm_bldrgst_pk
            -> .mgm_up_bldrgst_pk = 표제부(동).mgm_bldrgst_pk
               -> gold.complex_bld -> 단지

     돈암동 실측 14,666건 전수에서 네 단계가 전부 연결됐다 (결손 0).
     그래서 이 테이블은 **호명칭과 층만 들고 오면 되는 얇은 축**이다.

   ★ 라인은 코드가 없다. hoNm 에서 파생하는 수밖에 없고, 1,002호 실측 결과
     99%(994)가 `호번호 = 층*100 + 라인` 을 따른다. 깨지는 것은 상가·지하다:

        501-1호 · 501-3호 · B104호 · B102호 · B103호 · 1호

     **파생이 안 되면 NULL 로 둔다.** 추측으로 채우지 않는다 — 뼈대(동·층·호)는
     코드라 안 흔들리고, 라인만 모르는 것으로 남는다.
   ============================================================ */
USE Teomoony;
GO

IF OBJECT_ID('silver.bld_expos') IS NULL
CREATE TABLE silver.bld_expos (
    expos_sk         BIGINT IDENTITY(1,1) NOT NULL,
    mgm_bldrgst_pk   VARCHAR(50)   NOT NULL,   -- 호 자신의 PK (전유부는 호 단위 PK)
    sigungu_cd       CHAR(5)       NULL,
    bjdong_cd        CHAR(5)       NULL,
    plat_gb_cd       VARCHAR(1)    NULL,
    bun              VARCHAR(10)   NULL,
    ji               VARCHAR(10)   NULL,
    pnu              CHAR(19)      NULL,
    plat_plc         NVARCHAR(300) NULL,
    new_plat_plc     NVARCHAR(300) NULL,
    bld_nm           NVARCHAR(200) NULL,
    dong_nm          NVARCHAR(100) NULL,       -- 대조용. 동 연결은 PK 로 한다
    ho_nm            NVARCHAR(100) NULL,       -- ★ 이 축의 존재 이유
    flr_gb_cd        VARCHAR(2)    NULL,       -- 10 지하 / 20 지상
    flr_gb_nm        NVARCHAR(40)  NULL,
    flr_no           INT           NULL,
    regstr_gb_cd     VARCHAR(2)    NULL,
    regstr_gb_nm     NVARCHAR(40)  NULL,
    regstr_kind_cd   VARCHAR(2)    NULL,
    regstr_kind_nm   NVARCHAR(40)  NULL,
    na_road_cd       CHAR(12)      NULL,
    na_bjdong_cd     CHAR(5)       NULL,
    na_ugrnd_cd      VARCHAR(1)    NULL,
    na_main_bun      INT           NULL,
    na_sub_bun       INT           NULL,
    crtn_day         CHAR(8)       NULL,
    row_hash         BINARY(32)    NOT NULL,
    src_run_id       BIGINT        NULL,
    valid_from       DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    valid_to         DATETIME2(0)  NOT NULL DEFAULT '9999-12-31',
    is_current       BIT           NOT NULL DEFAULT 1,
    CONSTRAINT pk_bld_expos_ho PRIMARY KEY CLUSTERED (expos_sk)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='uq_bld_expos_current')
CREATE UNIQUE INDEX uq_bld_expos_current ON silver.bld_expos (mgm_bldrgst_pk) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_bld_expos_pnu')
CREATE INDEX ix_bld_expos_pnu ON silver.bld_expos (pnu) WHERE is_current = 1;
GO

/* ---------- 동 x 층 x 호 ----------
   **조인이 전부 PK 로만 간다.** 문자열은 한 군데도 쓰지 않는다.
   e(호) -> b(기본개요 전유부) -> 상위PK -> 동 -> 단지.

   `호_동명` 은 전유부가 같이 주는 동 이름이다. 코드로 이은 `동` 과 **대조용**으로
   둔다 — K-apt 연결에서 세대·동수를 같이 내려보낸 것과 같은 장치다.
   어긋나면 그게 발견이지 덮을 것이 아니다. */
IF OBJECT_ID('gold.v_complex_ho') IS NOT NULL DROP VIEW gold.v_complex_ho;
GO
CREATE VIEW gold.v_complex_ho
AS
SELECT cb.complex_id,
       동PK   = b.mgm_up_bldrgst_pk,
       호PK   = e.mgm_bldrgst_pk,
       동     = COALESCE(NULLIF(t.dong_nm,''), NULLIF(e.dong_nm,'')),
       호_동명 = e.dong_nm,                       -- 대조용 (코드로 이은 동과 비교)
       층구분 = e.flr_gb_nm,
       층     = CASE WHEN e.flr_gb_cd = '10' THEN -e.flr_no ELSE e.flr_no END,
       호     = e.ho_nm,
       /* 라인: 호번호 = 층*100 + 라인 일 때만. 아니면 NULL(모름).
          'B104호' · '501-1호' 처럼 숫자로 안 떨어지면 TRY_CONVERT 가 NULL 을 준다. */
       라인   = CASE WHEN TRY_CONVERT(INT, REPLACE(e.ho_nm, N'호', '')) / 100 = e.flr_no
                     THEN TRY_CONVERT(INT, REPLACE(e.ho_nm, N'호', '')) % 100 END,
       호번호 = TRY_CONVERT(INT, REPLACE(e.ho_nm, N'호', '')),
       e.pnu
FROM silver.bld_expos e
JOIN silver.bld_basis_outline b
  ON b.mgm_bldrgst_pk = e.mgm_bldrgst_pk
 AND b.is_current = 1 AND b.regstr_kind_cd = '4'
JOIN gold.complex_bld cb
  ON cb.mgm_bldrgst_pk = b.mgm_up_bldrgst_pk
LEFT JOIN silver.bld_title t
  ON t.mgm_bldrgst_pk = b.mgm_up_bldrgst_pk AND t.is_current = 1
WHERE e.is_current = 1;
GO

/* ---------- 적재 후 점검 ----------
   라인 파생이 몇 %에서 성립하는지, 코드로 이은 동과 전유부가 준 동이 어긋나는지. */
PRINT '--- 라인 파생 / 동 이름 대조 ---';
SELECT 호     = COUNT(*),
       라인있음 = SUM(CASE WHEN 라인 IS NOT NULL THEN 1 ELSE 0 END),
       라인없음 = SUM(CASE WHEN 라인 IS NULL THEN 1 ELSE 0 END),
       동이름_어긋남 = SUM(CASE WHEN NULLIF(호_동명,'') IS NOT NULL
                               AND 동 <> 호_동명 THEN 1 ELSE 0 END)
FROM gold.v_complex_ho;
GO

PRINT '26_expos done.';
GO
