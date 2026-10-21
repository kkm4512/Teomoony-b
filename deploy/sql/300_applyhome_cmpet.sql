/* ============================================================
   300_applyhome_cmpet : 청약홈 경쟁률 · 당첨가점 (2026-10-22, 사장님 활용신청 "완료")
   ★ 출처: odcloud ApplyhomeInfoCmpetRtSvc v1 (data.go.kr 15098905). 키 = DATA_GO_KR_KEY. 적재 etl/load_applyhome_cmpet.py
   ★ 한 줄 = 공고 × 주택형 × (순위) × (거주/우선 구분). 종류마다 구분 칸이 다르다:
       APT    : SUBSCRPT_RANK_CODE(1·2순위) × RESIDE_SECD(01 해당지역 · 02 기타경기 · 03 기타지역 …)
       URBTY  : RESIDNT_PRIOR_AT(거주자 우선 여부) · PBLPVT : SPSPLY_KND_CODE(공급 종류) · REMNDR : REMNDR_HSHLD_PBLANC_TYCD · OPT : 없음
     → 구분키 하나로 묶고(원문 이름은 구분이름) 기본키로 쓴다.
   ★ 경쟁률 원문은 그대로 둔다: '(△30)' = **미달 30세대**(접수가 공급보다 30 적다). 숫자로 바꾼 값은 따로(경쟁률 · 미달).
   ★ 가점 '-' 는 '없음'(NULL) — 0 점이 아니다.
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
IF OBJECT_ID('silver.applyhome_cmpet') IS NULL
CREATE TABLE silver.applyhome_cmpet (
    house_manage_no  VARCHAR(20)    NOT NULL,
    pblanc_no        VARCHAR(20)    NOT NULL,
    주택형           NVARCHAR(40)   NOT NULL,
    순위             TINYINT        NOT NULL,      -- APT 1·2, 나머지 0
    구분키           VARCHAR(20)    NOT NULL,
    구분이름         NVARCHAR(40)   NULL,
    공고종류         VARCHAR(10)    NOT NULL,
    model_no         VARCHAR(10)    NULL,
    공급             INT            NULL,
    접수             INT            NULL,
    경쟁률원문       NVARCHAR(40)   NULL,
    경쟁률           DECIMAL(12,2)  NULL,
    미달             INT            NULL,
    raw_json         NVARCHAR(MAX)  NULL,
    loaded_at        DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_applyhome_cmpet PRIMARY KEY CLUSTERED (house_manage_no, pblanc_no, 주택형, 순위, 구분키)
);
GO
IF OBJECT_ID('silver.applyhome_score') IS NULL
CREATE TABLE silver.applyhome_score (
    house_manage_no  VARCHAR(20)    NOT NULL,
    pblanc_no        VARCHAR(20)    NOT NULL,
    주택형           NVARCHAR(40)   NOT NULL,
    구분키           VARCHAR(20)    NOT NULL,
    구분이름         NVARCHAR(40)   NULL,
    model_no         VARCHAR(10)    NULL,
    최저             DECIMAL(6,2)   NULL,
    평균             DECIMAL(6,2)   NULL,
    최고             DECIMAL(6,2)   NULL,
    raw_json         NVARCHAR(MAX)  NULL,
    loaded_at        DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_applyhome_score PRIMARY KEY CLUSTERED (house_manage_no, pblanc_no, 주택형, 구분키)
);
GO
