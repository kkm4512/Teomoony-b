SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* ============================================================
   12_kapt : 공동주택 단지정보 (K-apt, 공동주택관리정보시스템)

   출처 : 목록   https://apis.data.go.kr/1613000/AptListService4/getLegaldongAptList4
          기본   https://apis.data.go.kr/1613000/AptBasisInfoServiceV5/getAphusBassInfoV5
          상세   https://apis.data.go.kr/1613000/AptBasisInfoServiceV5/getAphusDtlInfoV5
          * 셋 다 활용신청이 따로 필요하다.
          * 버전 접미가 서비스마다 다르다 (List 는 4, BasisInfo 는 V5).
          * 응답이 XML 이 아니라 JSON 이다.

   ★ 왜 필요한가 (CONTEXT.md 4-13, 4-15, 4-19)
     관리사무소 등록 기반이라 입주와 거의 동시에 올라온다. 건축물대장이
     못 따라오는 신축 구간을 메운다.
         장위자이레디언트(2,840세대, 2025.3 사용승인)
           대장 0 / 인허가 0 / 건물외곽선 0 / K-apt 있음
     전월세 645건이 붙을 곳이 없던 그 단지다.

   ★ gold.complex 에 넣지 않는다
     단지코드는 대장의 ROOT_PK 를 식별 근거로 삼아 재현된다(README 5장).
     출처가 다른 단지를 섞으면 재현성이 깨지고, 나중에 대장이 올라왔을 때
     같은 단지가 두 개가 된다. 별도 축으로 두고 PNU 로 잇는다.
   ============================================================ */
USE Teomoony;
GO

IF OBJECT_ID('silver.kapt_complex') IS NULL
CREATE TABLE silver.kapt_complex (
    kapt_sk        BIGINT IDENTITY(1,1) NOT NULL,
    kapt_code      VARCHAR(20)    NOT NULL,   -- A10020716
    kapt_name      NVARCHAR(200)  NULL,
    bjd_code       CHAR(10)       NULL,       -- 법정동코드 10. 이미 코드로 온다
    /* 지번은 kapt_addr 문자열에서 뽑는다. PNU 는 meta.fn_make_pnu() 로만 만든다.
       파싱이 실패하면 pnu 가 NULL 로 남는다(조용히 틀리느니 비워 둔다). */
    bun            VARCHAR(10)    NULL,
    ji             VARCHAR(10)    NULL,
    plat_gb_cd     VARCHAR(1)     NULL,       -- 0 대지 / 1 산
    pnu            CHAR(19)       NULL,
    kapt_addr      NVARCHAR(300)  NULL,
    doro_juso      NVARCHAR(300)  NULL,
    /* 규모 — 네이버 등이 보여주는 값들 */
    ho_cnt         INT            NULL,       -- 전체 세대수 (청약홈은 일반분양분뿐)
    dong_cnt       INT            NULL,
    kapt_usedate   CHAR(8)        NULL,       -- 사용승인일
    kapt_tarea     DECIMAL(18,4)  NULL,       -- 연면적
    kapt_marea     DECIMAL(18,4)  NULL,       -- 관리비부과면적
    priv_area      DECIMAL(18,4)  NULL,       -- 전용면적 합
    top_floor      INT            NULL,
    base_floor     INT            NULL,
    parking_cnt    DECIMAL(12,2)  NULL,       -- kaptdaCnt. 신축은 0 으로 오기도 한다
    code_apt_nm    NVARCHAR(40)   NULL,       -- 아파트 / 연립 ...
    code_sale_nm   NVARCHAR(40)   NULL,       -- 분양 / 임대 / 혼합
    code_heat_nm   NVARCHAR(40)   NULL,
    code_hall_nm   NVARCHAR(40)   NULL,
    code_mgr_nm    NVARCHAR(40)   NULL,
    bcompany       NVARCHAR(200)  NULL,       -- 시공사
    acompany       NVARCHAR(300)  NULL,       -- 시행사 (재개발이면 조합명이 들어온다)
    /* 상세 */
    mgr_cnt        INT            NULL,
    wtime_bus      NVARCHAR(40)   NULL,
    wtime_sub      NVARCHAR(40)   NULL,
    subway_line    NVARCHAR(80)   NULL,
    subway_station NVARCHAR(80)   NULL,
    use_yn         VARCHAR(2)     NULL,
    src            VARCHAR(30)    NOT NULL DEFAULT 'KAPT',
    row_hash       BINARY(32)     NOT NULL,
    src_run_id     BIGINT         NULL,
    valid_from     DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    valid_to       DATETIME2(0)   NOT NULL DEFAULT '9999-12-31',
    is_current     BIT            NOT NULL DEFAULT 1,
    CONSTRAINT pk_kapt_complex PRIMARY KEY CLUSTERED (kapt_sk)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='uq_kapt_current')
CREATE UNIQUE INDEX uq_kapt_current ON silver.kapt_complex (kapt_code) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_kapt_pnu')
CREATE INDEX ix_kapt_pnu ON silver.kapt_complex (pnu) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_kapt_bjd')
CREATE INDEX ix_kapt_bjd ON silver.kapt_complex (bjd_code) WHERE is_current = 1;
GO

/* ============================================================
   "실거래는 붙었는데 단지가 없는" 자리를 네 축으로 비교한다
   대장 / 인허가 / K-apt 중 어디에 있는지 한눈에 본다.
   ============================================================ */
IF OBJECT_ID('gold.v_newbuild_gap') IS NOT NULL DROP VIEW gold.v_newbuild_gap;
GO
CREATE VIEW gold.v_newbuild_gap
AS
SELECT t.pnu, t.lawd_cd,
       거래 = t.cnt,
       대장 = ISNULL(b.cnt, 0),
       인허가 = ISNULL(p.cnt, 0),
       kapt = ISNULL(k.cnt, 0),
       단지명 = k.kapt_name,
       세대 = k.ho_cnt,
       동수 = k.dong_cnt,
       사용승인 = k.kapt_usedate,
       시행 = k.acompany
FROM (
    SELECT match_pnu AS pnu, LEFT(match_pnu,10) AS lawd_cd, COUNT(*) AS cnt
    FROM silver.rtms_trade
    WHERE match_pnu IS NOT NULL AND match_complex_id IS NULL
    GROUP BY match_pnu
) t
OUTER APPLY (SELECT COUNT(*) AS cnt FROM silver.bld_basis_outline b
              WHERE b.is_current = 1 AND b.pnu = t.pnu) b
OUTER APPLY (SELECT COUNT(*) AS cnt FROM silver.arch_permit a
              WHERE a.is_current = 1 AND a.pnu = t.pnu) p
/* 여러 단지가 한 PNU 를 쓸 수 있다(장위자이레디언트 1~4단지). 건수와 대표 1건을
   따로 뽑는다. 컬럼별 MAX 로 섞으면 4-16 의 실수를 반복한다. */
OUTER APPLY (SELECT COUNT(*) AS cnt FROM silver.kapt_complex k
              WHERE k.is_current = 1 AND k.pnu = t.pnu) k2
OUTER APPLY (
    SELECT TOP 1 kapt_name, ho_cnt, dong_cnt, kapt_usedate, acompany, cnt = k2.cnt
    FROM silver.kapt_complex k
    WHERE k.is_current = 1 AND k.pnu = t.pnu
    ORDER BY k.ho_cnt DESC, k.kapt_code
) k;
GO
