/* ============================================================
   320_juso : 행정안전부 도로명주소 검색 API(business.juso.go.kr addrLinkApi, .env JUSO_KEY 운영키) — 물어본 주소와 받은 원문 (2026-10-23 사장님 "운영키 .env 에 넣고 1번 ㄱㄱ")
   ★ 사장님 "법정동 도로명 모두 마스터와 같은 방식을 활용해야해" — 주소 글자끼리 비교하지 않고, **공식 코드**(도로명코드 12 · 건물본번/부번 · 법정동코드 · 지번 → PNU)로 잇는다.
     받은 도로명코드는 meta.road_code(도로명 마스터)에도 넣는다 — 법정동 마스터(meta.lawd_code)와 같은 자리.
     ⚠ 지금은 물어본 주소에 나온 도로만 들어간다(전체분 파일을 받으면 그걸로 채운다).
   ★ 원문 그대로 — 응답 JSON 을 통째로 남기고(raw), 칸은 펼쳐 둔다. 같은 질의는 다시 묻지 않는다.
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
IF OBJECT_ID('silver.juso_lookup') IS NULL
CREATE TABLE silver.juso_lookup (
    keyword       NVARCHAR(300) NOT NULL CONSTRAINT pk_juso_lookup PRIMARY KEY,
    출처          VARCHAR(20)   NOT NULL,          -- KAPT | RTMS | CLOSED ...
    total_count   INT           NULL,
    error_code    VARCHAR(20)   NULL,
    error_message NVARCHAR(400) NULL,
    raw           NVARCHAR(MAX) NULL,
    받은때        DATETIME2(0)  NOT NULL CONSTRAINT df_juso_lookup_t DEFAULT SYSDATETIME()
);
GO
IF OBJECT_ID('silver.juso_result') IS NULL
CREATE TABLE silver.juso_result (
    keyword     NVARCHAR(300) NOT NULL,
    순          INT           NOT NULL,
    road_addr   NVARCHAR(400) NULL,
    jibun_addr  NVARCHAR(400) NULL,
    adm_cd      CHAR(10)      NULL,     -- 법정동코드
    rn_mgt_sn   CHAR(12)      NULL,     -- 도로명코드(시군구 5 + 도로 7)
    rn          NVARCHAR(100) NULL,     -- 도로명
    udrt_yn     CHAR(1)       NULL,
    buld_mnnm   INT           NULL,
    buld_slno   INT           NULL,
    mt_yn       CHAR(1)       NULL,
    lnbr_mnnm   INT           NULL,
    lnbr_slno   INT           NULL,
    bd_mgt_sn   VARCHAR(30)   NULL,     -- 건물관리번호
    bd_nm       NVARCHAR(200) NULL,
    bd_kdcd     CHAR(1)       NULL,     -- 공동주택 1
    pnu         AS CAST(adm_cd + CASE WHEN mt_yn = '1' THEN '2' ELSE '1' END
                        + RIGHT('0000' + CAST(lnbr_mnnm AS VARCHAR(4)), 4) + RIGHT('0000' + CAST(ISNULL(lnbr_slno, 0) AS VARCHAR(4)), 4) AS CHAR(19)) PERSISTED,
    CONSTRAINT pk_juso_result PRIMARY KEY (keyword, 순)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_juso_result_pnu' AND object_id = OBJECT_ID('silver.juso_result'))
    CREATE INDEX ix_juso_result_pnu ON silver.juso_result (pnu);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_juso_result_road' AND object_id = OBJECT_ID('silver.juso_result'))
    CREATE INDEX ix_juso_result_road ON silver.juso_result (rn_mgt_sn, buld_mnnm, buld_slno);
GO
/* 물어볼 말 — K-apt 도로명주소를 '시도 시군구 도로명 건물번호' 까지(뒤 단지 이름 · 괄호를 뗀다). 317 과 같은 자르기 */
CREATE OR ALTER VIEW gold.v_juso_ask_kapt
AS
SELECT DISTINCT keyword = CAST(LTRIM(RTRIM(LEFT(k.doro_juso, PATINDEX('%[0-9] %', k.doro_juso + ' ')))) AS NVARCHAR(300))
  FROM silver.kapt_complex k
 WHERE k.is_current = 1 AND k.doro_juso LIKE N'%[0-9]%' AND (k.bjd_code LIKE '11%' OR k.bjd_code LIKE '4117%');
GO
/* 도로명 마스터에 받은 도로 넣기 — 받은 뒤 부른다 */
CREATE OR ALTER PROCEDURE meta.usp_road_code_from_juso
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO meta.road_code (road_cd, road_nm)
    SELECT r.rn_mgt_sn, MIN(r.rn) FROM silver.juso_result r
     WHERE r.rn_mgt_sn IS NOT NULL AND NOT EXISTS (SELECT 1 FROM meta.road_code m WHERE m.road_cd = r.rn_mgt_sn)
     GROUP BY r.rn_mgt_sn;
    SELECT 도로 = (SELECT COUNT(*) FROM meta.road_code);
END
GO
SELECT 물을말 = (SELECT COUNT(*) FROM gold.v_juso_ask_kapt), 받음 = (SELECT COUNT(*) FROM silver.juso_lookup), 도로 = (SELECT COUNT(*) FROM meta.road_code);
