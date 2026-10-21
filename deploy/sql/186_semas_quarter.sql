/* 186. 상권 분기 스냅샷 (2026-10-19)
   출처: 소상공인시장진흥공단_상가(상권)정보 (data.go.kr 15083033)
         분기 CSV · 시도별로 나뉨 · **이용허락범위 제한 없음** · utf-8
         과거 분기 49개가 '주기성 과거 데이터' 로 전부 열려 있다.

   ★ 왜 필요한가 — API 는 '지금 영업중' 만 준다
     `silver.semas_store` 는 스냅샷이라 **폐업을 볼 수 없다.**
     분기 파일을 쌓아야 "1년 새 몇 곳이 사라지고 몇 곳이 생겼나" 를 말할 수 있다.

   ★ bizes_id 는 분기를 넘어 유지된다 — 실측(185)
     2025-06 성북·종로·은평 52,101건에서 1,000건을 뽑아 2026-10 스냅샷과 대조:
     **871건이 그대로 있었다.** id 가 재발급됐다면 0 에 가까웠을 것이다.
     그래서 '과거에 있고 지금 없다' 를 폐업의 신호로 쓸 수 있다.

   ★ 다만 **수집 경계가 다르다.**
     과거 CSV 는 시군구 기준, 현재 스냅샷은 법정동 bbox 기준이다.
     그래서 '사라진 것' 을 셀 때는 반드시 **단지 반경 안으로 잘라서** 센다.
     경계가 다른 둘을 통째로 빼면 '안 받은 구역' 이 폐업으로 둔갑한다.
*/
IF OBJECT_ID('silver.semas_quarter') IS NULL
CREATE TABLE silver.semas_quarter (
    q_sk          BIGINT IDENTITY(1,1) NOT NULL,
    quarter       CHAR(6)        NOT NULL,   -- 202506
    bizes_id      VARCHAR(30)    NOT NULL,
    bizes_nm      NVARCHAR(200)  NULL,
    inds_lcls_cd  VARCHAR(4)     NULL,
    inds_lcls_nm  NVARCHAR(60)   NULL,
    inds_mcls_cd  VARCHAR(6)     NULL,
    inds_mcls_nm  NVARCHAR(60)   NULL,
    inds_scls_cd  VARCHAR(8)     NULL,
    inds_scls_nm  NVARCHAR(80)   NULL,
    signgu_cd     CHAR(5)        NULL,
    ldong_cd      CHAR(10)       NULL,
    pnu           CHAR(19)       NULL,       -- ★ 원본 '지번코드' 가 PNU 19자리다
    bld_mng_no    VARCHAR(30)    NULL,
    lon           DECIMAL(12,8)  NULL,
    lat           DECIMAL(11,8)  NULL,
    geog          geography      NULL,
    CONSTRAINT pk_semas_quarter PRIMARY KEY CLUSTERED (q_sk)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='uq_semas_quarter')
CREATE UNIQUE INDEX uq_semas_quarter ON silver.semas_quarter (quarter, bizes_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='sx_semas_quarter_geog')
CREATE SPATIAL INDEX sx_semas_quarter_geog ON silver.semas_quarter (geog);
GO
PRINT '186 완료 - silver.semas_quarter';
