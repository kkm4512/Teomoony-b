/* 306_ned_aphus_price : 공동주택가격(VWorld NED getApartHousingPriceAttr) — 연립·다세대 채우기 (2026-10-22 14:13 사장님 "1 ㄱㄱ")
   왜: 건축HUB getBrHsprcInfo(27, silver.bld_hsprc)가 **연립·다세대를 거의 안 준다**(성북 연립 6,225호 중 62 · 다세대 30,993호 중 1).
       NED 공동주택가격은 다세대도 준다(드림아트빌 101호 2026 2.28억).
   ★ 원문 그대로(동명·호명·층·전용·공시가격·공동주택코드·구분). 대상 = 전유부에 연립(02002)·다세대(02003) 호가 있는 필지.
   ★ 호 잇기(gold.v_ned_ho_price): 같은 PNU 안에서 **동명·호명이 같은 호가 하나**일 때만(공백·'동'·'호' 글자 차이는 맞춘다). 이름(단지명)은 안 쓴다.
*/
SET NOCOUNT ON;
GO
IF OBJECT_ID('silver.ned_aphus_price') IS NULL
CREATE TABLE silver.ned_aphus_price (
    pnu          CHAR(19)       NOT NULL,
    기준연도     CHAR(4)        NOT NULL,
    기준월       CHAR(2)        NOT NULL,
    공동주택코드 VARCHAR(20)    NOT NULL,      -- aphusCode
    동명         NVARCHAR(100)  NOT NULL,      -- dongNm ('' 그대로)
    호명         NVARCHAR(100)  NOT NULL,      -- hoNm
    층           NVARCHAR(20)   NULL,          -- floorNm
    전용면적     DECIMAL(12,4)  NULL,          -- prvuseAr
    공시가격     BIGINT         NULL,          -- pblntfPc (원)
    공동주택명   NVARCHAR(200)  NULL,          -- aphusNm
    구분         NVARCHAR(20)   NULL,          -- aphusSeCodeNm (아파트·연립·다세대)
    대장구분     NVARCHAR(20)   NULL,
    특수지명     NVARCHAR(100)  NULL,
    원문갱신일   CHAR(10)       NULL,
    받은시각     DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_ned_aphus_price PRIMARY KEY CLUSTERED (pnu, 공동주택코드, 동명, 호명, 기준연도, 기준월)
);
GO
IF OBJECT_ID('silver.ned_aphus_done') IS NULL
CREATE TABLE silver.ned_aphus_done (
    pnu        CHAR(19)     NOT NULL CONSTRAINT pk_ned_aphus_done PRIMARY KEY,
    건수       INT          NOT NULL,
    받은시각   DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()
);
GO
