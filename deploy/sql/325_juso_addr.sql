/* ============================================================
   325_juso_addr : 도로명주소 전체(서울·안양) — 법정동마다 juso 검색 API 를 끝 쪽까지 (2026-10-23 사장님 "도로명주소 key있고, 우리 전체 법정동 가지고있잖아 다 API쏴서 알아와")
   ★ 물을 말 = meta.lawd_code 의 법정동 이름 그대로(시도 시군구 읍면동). 받은 것 중 admCd = 그 법정동인 것만 담는다(이름이 겹친 다른 동 버림).
   ★ 원문 칸 그대로 · 건물관리번호(bd_mgt_sn)마다 1줄. 시군구마다 지우고 다시 넣는다(공식 API 의 복사본).
   ★ 다 받은 법정동만 _done 에 '다 받음'(받은 줄 = totalCount 중 이 동 것) — 못 본 것은 닫지 않는다.
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
IF OBJECT_ID('silver.juso_addr') IS NULL
CREATE TABLE silver.juso_addr (
    bd_mgt_sn   VARCHAR(30)   NOT NULL CONSTRAINT pk_juso_addr PRIMARY KEY,
    adm_cd      CHAR(10)      NOT NULL,
    rn_mgt_sn   CHAR(12)      NULL,
    rn          NVARCHAR(100) NULL,
    udrt_yn     CHAR(1)       NULL,
    buld_mnnm   INT           NULL,
    buld_slno   INT           NULL,
    mt_yn       CHAR(1)       NULL,
    lnbr_mnnm   INT           NULL,
    lnbr_slno   INT           NULL,
    bd_nm       NVARCHAR(200) NULL,
    bd_kdcd     CHAR(1)       NULL,
    det_bd_nm   NVARCHAR(1000) NULL,   -- 상세건물명(동 이름들) 원문
    zip_no      CHAR(5)       NULL,
    road_addr   NVARCHAR(400) NULL,
    jibun_addr  NVARCHAR(400) NULL,
    pnu         AS CAST(adm_cd + CASE WHEN mt_yn = '1' THEN '2' ELSE '1' END
                        + RIGHT('0000' + CAST(lnbr_mnnm AS VARCHAR(4)), 4) + RIGHT('0000' + CAST(ISNULL(lnbr_slno, 0) AS VARCHAR(4)), 4) AS CHAR(19)) PERSISTED,
    sgg_cd      AS CAST(LEFT(adm_cd, 5) AS CHAR(5)) PERSISTED,
    받은때      DATETIME2(0)  NOT NULL CONSTRAINT df_juso_addr_t DEFAULT SYSDATETIME()
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_juso_addr_pnu' AND object_id = OBJECT_ID('silver.juso_addr'))
    CREATE INDEX ix_juso_addr_pnu ON silver.juso_addr (pnu);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_juso_addr_road' AND object_id = OBJECT_ID('silver.juso_addr'))
    CREATE INDEX ix_juso_addr_road ON silver.juso_addr (rn_mgt_sn, buld_mnnm, buld_slno);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_juso_addr_sgg' AND object_id = OBJECT_ID('silver.juso_addr'))
    CREATE INDEX ix_juso_addr_sgg ON silver.juso_addr (sgg_cd);
GO
IF OBJECT_ID('silver.juso_addr_done') IS NULL
CREATE TABLE silver.juso_addr_done (
    lawd_cd     CHAR(10)     NOT NULL CONSTRAINT pk_juso_addr_done PRIMARY KEY,
    keyword     NVARCHAR(200) NOT NULL,
    total_count INT          NULL,     -- API 가 말한 전체(이름 겹친 다른 동 포함)
    받은줄      INT          NULL,     -- 그중 이 법정동 것
    다받음      BIT          NOT NULL,
    받은때      DATETIME2(0) NOT NULL CONSTRAINT df_juso_addr_done_t DEFAULT SYSDATETIME()
);
GO
/* 도로 마스터: 물어본 주소(juso_result) + 전체 주소(juso_addr) 의 도로명코드 */
CREATE OR ALTER PROCEDURE meta.usp_road_code_from_juso
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO meta.road_code (road_cd, road_nm)
    SELECT x.rn_mgt_sn, MIN(x.rn)
      FROM (SELECT rn_mgt_sn, rn FROM silver.juso_result WHERE rn_mgt_sn IS NOT NULL
            UNION ALL SELECT rn_mgt_sn, rn FROM silver.juso_addr WHERE rn_mgt_sn IS NOT NULL) x
     WHERE NOT EXISTS (SELECT 1 FROM meta.road_code m WHERE m.road_cd = x.rn_mgt_sn)
     GROUP BY x.rn_mgt_sn;
    SELECT 도로 = (SELECT COUNT(*) FROM meta.road_code);
END
GO
SELECT 법정동 = (SELECT COUNT(*) FROM meta.lawd_code WHERE is_abolished = 0 AND ri_nm IS NULL AND emd_nm IS NOT NULL AND (lawd_cd LIKE '11%' OR LEFT(lawd_cd,5) IN ('41171','41173'))),
       받은동 = (SELECT COUNT(*) FROM silver.juso_addr_done), 주소 = (SELECT COUNT(*) FROM silver.juso_addr);
