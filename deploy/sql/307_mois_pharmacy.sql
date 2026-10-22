/* 307_mois_pharmacy : 행정안전부 약국 인허가(apis.data.go.kr/1741000/pharmacies/info) (2026-10-22 14:13 사장님 "붙여 ㄱㄱ")
   심평원 약국(295)과 출처가 다르다 — 이쪽은 **인허가 원부**라 폐업·휴업 이력까지 있다. 섞지 않고 따로 적는다.
   좌표 원문 CRD_INFO_X/Y = EPSG:5174(LOCALDATA) → 적재기에서 WGS84 로 바꿔 lat/lng(원문도 같이 둔다).
   범위: 지번주소가 서울특별시 · 경기도 안양시 로 시작하는 것.
*/
SET NOCOUNT ON;
GO
IF OBJECT_ID('silver.mois_pharmacy') IS NULL
CREATE TABLE silver.mois_pharmacy (
    관리번호     VARCHAR(40)    NOT NULL CONSTRAINT pk_mois_pharmacy PRIMARY KEY,   -- MNG_NO
    이름         NVARCHAR(200)  NULL,
    영업상태     NVARCHAR(20)   NULL,          -- SALS_STTS_NM (영업/정상 · 폐업 · 휴업 …)
    상세상태     NVARCHAR(20)   NULL,          -- DTL_SALS_STTS_NM
    인허가일     CHAR(10)       NULL,
    폐업일       CHAR(10)       NULL,
    휴업시작     CHAR(10)       NULL,
    휴업끝       CHAR(10)       NULL,
    인허가취소일 CHAR(10)       NULL,
    지번주소     NVARCHAR(300)  NULL,
    도로명주소   NVARCHAR(300)  NULL,
    전화         VARCHAR(40)    NULL,
    자치단체코드 VARCHAR(10)    NULL,
    x_5174       DECIMAL(14,4)  NULL,
    y_5174       DECIMAL(14,4)  NULL,
    lat          DECIMAL(10,7)  NULL,
    lng          DECIMAL(10,7)  NULL,
    geog         GEOGRAPHY      NULL,
    원문갱신     VARCHAR(30)    NULL,          -- DAT_UPDT_PNT
    받은시각     DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME()
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'sx_mois_pharmacy_geog')
    CREATE SPATIAL INDEX sx_mois_pharmacy_geog ON silver.mois_pharmacy (geog);
GO
