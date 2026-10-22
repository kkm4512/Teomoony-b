/* 305_land_move : 토지 이동 이력 (2026-10-22 13:55, 사장님 "서울,안양 기준으로 일단 다 받아봐")
   출처: VWorld 국가중점데이터 getLandMoveAttr(토지이동이력속성조회) — 필지(PNU)마다 이력: 일자 · 사유(원문, '68-11번에서 분할' · '토지개발사업 시행신고' …) · 지목 · 면적.
   ★ 원문 그대로. 사유 글에서 옛/새 지번을 뽑아 잇는 일은 여기서 하지 않는다(필요하면 따로, 근거를 남겨서).
   ★ 받는 차례: ① 청약 공고 지번 중 지금 지적도에 없는 것 ② 폐쇄·말소 대장 필지 중 지금 지적도에 없는 것 ③ 서울·안양 지금 필지 전부.
   ★ 다 받은 필지는 silver.land_move_done(이력 0건도 '다 받음'). 이어받기 = done 에 없는 것만.
*/
SET NOCOUNT ON;
GO
IF OBJECT_ID('silver.land_move_hist') IS NULL
CREATE TABLE silver.land_move_hist (
    pnu            CHAR(19)       NOT NULL,
    대장코드       VARCHAR(2)     NOT NULL,      -- regstrSeCode 1 토지대장 · 2 임야대장
    이력순번       VARCHAR(10)    NOT NULL,      -- ladHistSn
    이력일련       VARCHAR(20)    NULL,          -- ladMvmnHistSn
    대장           NVARCHAR(20)   NULL,
    이동일         CHAR(10)       NULL,          -- ladMvmnDe
    이동사유코드   VARCHAR(10)    NULL,
    이동사유       NVARCHAR(200)  NULL,          -- ladMvmnPrvonshCodeNm (원문)
    소멸일         CHAR(10)       NULL,          -- ladMvmnErsrDe ('' 면 NULL)
    지번           NVARCHAR(40)   NULL,          -- mnnmSlno
    지목코드       VARCHAR(4)     NULL,
    지목           NVARCHAR(20)   NULL,
    면적           DECIMAL(19,2)  NULL,
    원문갱신일     CHAR(10)       NULL,          -- lastUpdtDt
    받은시각       DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_land_move_hist PRIMARY KEY CLUSTERED (pnu, 대장코드, 이력순번)
);
GO
IF OBJECT_ID('silver.land_move_done') IS NULL
CREATE TABLE silver.land_move_done (
    pnu        CHAR(19)      NOT NULL CONSTRAINT pk_land_move_done PRIMARY KEY,
    건수       INT           NOT NULL,
    차례       TINYINT       NOT NULL,           -- 1 공고 · 2 폐쇄 · 3 지금 필지
    받은시각   DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);
GO
