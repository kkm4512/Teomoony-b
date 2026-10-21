/* 169. 상가(상권)정보 — 점포 (2026-10-19)
   출처: 소상공인시장진흥공단_상가(상권)정보_API (data.go.kr 15012005)
         엔드포인트 apis.data.go.kr/B553077/api/open/sdsc2
         **이용허락범위 제한 없음** · 원자료 출처 국세청/카드사 · 분기 갱신

   ★ 코드로 붙는다 — 반경만으로 잇지 않는다
     응답에 `lnoCd` 가 **PNU 19자리**, `bldMngNo` 가 **건물관리번호 25자리**로 온다.
     즉 `silver.cadastral_parcel.pnu`, `silver.building_footprint.bd_mgt_sn` 과
     **그대로 조인된다.** 정책 1장이 말하는 '코드로 잇기' 가 여기서도 된다.
     반경은 '주변 상권' 을 재는 용도지, 소속을 정하는 용도가 아니다.

   ★ 거리는 geography 로 잰다
     300/500/1000m 는 **미터**다. geometry(4326) 의 STDistance 는 도(degree)라
     미터가 아니다. 이 표의 쓰임은 전부 미터 거리라 geography 를 쓴다.

   ★ 업종은 코드에 계층이 박혀 있다 — 대2 / 중4 / 소6 자리.
     이름을 파싱하지 않아도 LEFT(코드,2) 로 대분류가 떨어진다.
     (어제 용도지역은 이름을 LIKE 로 묶어야 했다. 이쪽이 낫다.)
*/
IF OBJECT_ID('silver.semas_store') IS NULL
CREATE TABLE silver.semas_store (
    store_sk      BIGINT IDENTITY(1,1) NOT NULL,
    bizes_id      VARCHAR(30)    NOT NULL,   -- 상가업소번호 (자연키)
    bizes_nm      NVARCHAR(200)  NULL,
    brch_nm       NVARCHAR(100)  NULL,
    inds_lcls_cd  VARCHAR(4)     NULL,       -- 대분류 2자리
    inds_lcls_nm  NVARCHAR(60)   NULL,
    inds_mcls_cd  VARCHAR(6)     NULL,       -- 중분류 4자리
    inds_mcls_nm  NVARCHAR(60)   NULL,
    inds_scls_cd  VARCHAR(8)     NULL,       -- 소분류 6자리
    inds_scls_nm  NVARCHAR(80)   NULL,
    ksic_cd       VARCHAR(10)    NULL,       -- 표준산업분류 10차
    ksic_nm       NVARCHAR(100)  NULL,
    signgu_cd     CHAR(5)        NULL,
    adong_cd      VARCHAR(10)    NULL,
    adong_nm      NVARCHAR(60)   NULL,
    ldong_cd      CHAR(10)       NULL,
    ldong_nm      NVARCHAR(60)   NULL,
    pnu           CHAR(19)       NULL,       -- ★ lnoCd. 필지와 그대로 조인된다
    lno_adr       NVARCHAR(300)  NULL,
    bld_mng_no    VARCHAR(30)    NULL,       -- ★ 건물관리번호. 건물 외곽선과 조인
    bld_nm        NVARCHAR(200)  NULL,
    rdnm_adr      NVARCHAR(300)  NULL,
    flr_no        NVARCHAR(20)   NULL,
    ho_no         NVARCHAR(20)   NULL,
    lon           DECIMAL(12,8)  NULL,
    lat           DECIMAL(11,8)  NULL,
    geog          geography      NULL,       -- SRID 4326. 거리는 미터로 나온다
    collected_at  CHAR(8)        NULL,       -- 받은 날 (API 는 '현재 영업중' 스냅샷이다)
    row_hash      BINARY(32)     NOT NULL,
    src_run_id    BIGINT         NULL,
    valid_from    DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    valid_to      DATETIME2(0)   NOT NULL DEFAULT '9999-12-31',
    is_current    BIT            NOT NULL DEFAULT 1,
    CONSTRAINT pk_semas_store PRIMARY KEY CLUSTERED (store_sk)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='uq_semas_current')
CREATE UNIQUE INDEX uq_semas_current ON silver.semas_store (bizes_id) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_semas_pnu')
CREATE INDEX ix_semas_pnu ON silver.semas_store (pnu)
    INCLUDE (inds_lcls_cd, bizes_nm) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_semas_bld')
CREATE INDEX ix_semas_bld ON silver.semas_store (bld_mng_no) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_semas_ldong')
CREATE INDEX ix_semas_ldong ON silver.semas_store (ldong_cd, inds_lcls_cd) WHERE is_current = 1;
GO
/* 공간 인덱스 — 반경 집계가 이것 없이는 전수 스캔이다 */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='sx_semas_geog')
CREATE SPATIAL INDEX sx_semas_geog ON silver.semas_store (geog);
GO
PRINT '169 완료 — silver.semas_store';
