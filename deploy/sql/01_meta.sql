SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* ============================================================
   Teomoony - 01_meta : 기준정보(코드) 레이어
   ============================================================ */
USE Teomoony;
GO

/* ---------- 법정동코드 (행정표준코드관리시스템) ----------
   PNU 앞 10자리의 원천. 이게 없으면 어떤 연계도 성립하지 않음.
   폐지 코드도 보존해야 한다 - 과거 건축물대장이 폐지 법정동을 참조함. */
IF OBJECT_ID('meta.lawd_code') IS NULL
CREATE TABLE meta.lawd_code (
    lawd_cd          CHAR(10)      NOT NULL,   -- 법정동코드 10
    sido_nm          NVARCHAR(40)  NULL,
    sgg_nm           NVARCHAR(40)  NULL,
    emd_nm           NVARCHAR(40)  NULL,
    ri_nm            NVARCHAR(40)  NULL,
    full_nm          NVARCHAR(200) NULL,
    is_abolished     BIT           NOT NULL DEFAULT 0,
    sido_cd          AS CAST(LEFT(lawd_cd,2) AS CHAR(2))  PERSISTED,
    sgg_cd           AS CAST(LEFT(lawd_cd,5) AS CHAR(5))  PERSISTED,
    emd_cd           AS CAST(SUBSTRING(lawd_cd,6,3) AS CHAR(3)) PERSISTED,
    loaded_at        DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_lawd_code PRIMARY KEY CLUSTERED (lawd_cd)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_lawd_sgg')
CREATE INDEX ix_lawd_sgg ON meta.lawd_code (sgg_cd) INCLUDE (emd_nm, is_abolished);
GO

/* ---------- 도로명코드 ----------
   도로명코드 12 = 시군구코드5 + 도로명번호7 */
IF OBJECT_ID('meta.road_code') IS NULL
CREATE TABLE meta.road_code (
    road_cd          CHAR(12)      NOT NULL,
    sgg_cd           AS CAST(LEFT(road_cd,5) AS CHAR(5)) PERSISTED,
    road_nm          NVARCHAR(80)  NULL,
    road_nm_eng      VARCHAR(160)  NULL,
    emd_cd           CHAR(10)      NULL,
    emd_serial_no    CHAR(2)       NULL,
    loaded_at        DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_road_code PRIMARY KEY CLUSTERED (road_cd)
);
GO

/* ---------- 공통 코드 (주용도/구조/지목 등) ---------- */
IF OBJECT_ID('meta.code_item') IS NULL
CREATE TABLE meta.code_item (
    code_group       VARCHAR(40)   NOT NULL,   -- MAIN_PURPS | STRCT | JIMOK | PLAT_GB ...
    code_val         VARCHAR(20)   NOT NULL,
    code_nm          NVARCHAR(200) NULL,
    sort_no          INT           NULL,
    CONSTRAINT pk_code_item PRIMARY KEY CLUSTERED (code_group, code_val)
);
GO

/* 대지구분 매핑 - 건축물대장 platGbCd(0/1/2) vs PNU 대지구분(1/2)
   이 불일치가 PNU 조립 사고의 1순위 원인이므로 코드로 못박아 둔다. */
MERGE meta.code_item AS t
USING (VALUES
    ('PLAT_GB','0',N'대지',1),
    ('PLAT_GB','1',N'산',2),
    ('PLAT_GB','2',N'블록',3),
    ('PNU_SAN','1',N'일반(대지)',1),
    ('PNU_SAN','2',N'산',2)
) AS s(code_group, code_val, code_nm, sort_no)
ON t.code_group = s.code_group AND t.code_val = s.code_val
WHEN NOT MATCHED THEN INSERT (code_group, code_val, code_nm, sort_no)
     VALUES (s.code_group, s.code_val, s.code_nm, s.sort_no);
GO

/* ============================================================
   PNU 조립 함수
   PNU(19) = 법정동코드10 + 대지구분1 + 본번4 + 부번4
   주의: 건축물대장 platGbCd 0=대지 -> PNU '1'
                              1=산   -> PNU '2'
                              2=블록 -> PNU '1' (대지로 취급)
   ============================================================ */
IF OBJECT_ID('meta.fn_make_pnu') IS NOT NULL DROP FUNCTION meta.fn_make_pnu;
GO
CREATE FUNCTION meta.fn_make_pnu (
    @sigungu_cd  VARCHAR(5),    -- 시군구코드 5
    @bjdong_cd   VARCHAR(5),    -- 법정동코드 뒤 5 (읍면동3 + 리2)
    @plat_gb_cd  VARCHAR(1),    -- 건축물대장 platGbCd
    @bun         VARCHAR(10),
    @ji          VARCHAR(10)
)
RETURNS CHAR(19)
AS
BEGIN
    IF @sigungu_cd IS NULL OR @bjdong_cd IS NULL RETURN NULL;
    IF LEN(@sigungu_cd) <> 5 OR LEN(@bjdong_cd) <> 5 RETURN NULL;

    DECLARE @san CHAR(1) =
        CASE LTRIM(RTRIM(ISNULL(@plat_gb_cd,'0')))
             WHEN '1' THEN '2'   -- 산
             WHEN '2' THEN '1'   -- 블록 -> 대지 취급
             ELSE '1'            -- 0 또는 NULL -> 대지
        END;

    DECLARE @b VARCHAR(10) = NULLIF(LTRIM(RTRIM(ISNULL(@bun,''))),'');
    DECLARE @j VARCHAR(10) = NULLIF(LTRIM(RTRIM(ISNULL(@ji ,''))),'');

    /* 숫자 아닌 값이 섞여 오는 경우가 있어 방어 */
    IF @b IS NOT NULL AND TRY_CAST(@b AS INT) IS NULL RETURN NULL;
    IF @j IS NOT NULL AND TRY_CAST(@j AS INT) IS NULL RETURN NULL;

    RETURN CAST(
             @sigungu_cd + @bjdong_cd + @san
           + RIGHT('0000' + CAST(ISNULL(TRY_CAST(@b AS INT),0) AS VARCHAR(10)), 4)
           + RIGHT('0000' + CAST(ISNULL(TRY_CAST(@j AS INT),0) AS VARCHAR(10)), 4)
           AS CHAR(19));
END
GO

/* PNU -> 사람이 읽는 지번 문자열 */
IF OBJECT_ID('meta.fn_pnu_to_jibun') IS NOT NULL DROP FUNCTION meta.fn_pnu_to_jibun;
GO
/* ★★ 2026-10-21: **한 문장으로 고쳤다.** 규칙은 글자 그대로 같다 — 바꾼 것은 모양뿐이다.

   왜: 전에는 IF · DECLARE 가 있는 **다중 문장** 스칼라 UDF 였다. 그런 함수는
     SQL Server 가 **인라인하지 못하고** 행마다 호출하며, 그 쿼리를 **직렬**로 만든다.
     gold.v_complex_map 이 이 함수로 rep_jibun 을 만들기 때문에 **단지 검색 전체**가
     그 비용을 뒤집어썼다 — 실측(2026-10-21, 적재 중):
         표를 직접 세면            957~1,245ms
         이 함수가 낀 뷰로 세면    6,524ms
         한 문장으로 바꾼 뒤       1,164ms   (7,254ms -> 1,164ms)
     공개 사이트의 검색이 7~9초였던 원인이 이것이다.

   ★ **식을 뷰에 풀어 쓰지 않았다.** 그러면 지번 만드는 규칙이 두 군데가 된다
     (작업방식 10장). 규칙은 여기 한 곳에 두고 **함수의 모양만** 바꾼다.
   ★ 바꾸기 전 `fn_pnu_to_jibun2` 로 만들어 **538,377행 전수 대조**했다 —
     EXCEPT 로 양쪽, **다른건수 0**. (`=` 로 비교하면 NULL 때문에 전부 '다름' 이 된다.)
   ★ 호환 수준 160 이라 인라이닝이 돈다. 더 낮은 서버로 옮기면 다시 느려진다. */
CREATE FUNCTION meta.fn_pnu_to_jibun (@pnu CHAR(19))
RETURNS NVARCHAR(200)
AS
BEGIN
    RETURN CASE WHEN @pnu IS NULL OR LEN(@pnu) <> 19 THEN NULL
        ELSE CASE SUBSTRING(@pnu,11,1) WHEN '2' THEN N'산 ' ELSE N'' END
             + CAST(TRY_CAST(SUBSTRING(@pnu,12,4) AS INT) AS NVARCHAR(10))
             + CASE WHEN ISNULL(TRY_CAST(SUBSTRING(@pnu,16,4) AS INT),0) > 0
                    THEN N'-' + CAST(TRY_CAST(SUBSTRING(@pnu,16,4) AS INT) AS NVARCHAR(10))
                    ELSE N'' END
    END
END
GO

PRINT '01_meta done.';
GO
