/* 2026-10-24 10:36 사장님 "학교 상세는 모달로 · 더 많은 데이터" — 학교알리미 '전·출입 및 학업중단 학생 수'(apiType 10) 공시값 그대로.
   전입 MVIN_SUM · 전출 MVT_SUM · 전체 STDNT_SUM(이 항목 기준). 학년별 원문은 raw_json. */
IF OBJECT_ID('silver.schoolinfo_move') IS NULL
CREATE TABLE silver.schoolinfo_move (
    schul_code   VARCHAR(12)   NOT NULL,
    pban_yr      SMALLINT      NOT NULL,
    mvin_cnt     INT           NULL,
    mvt_cnt      INT           NULL,
    stdnt_cnt    INT           NULL,
    excp_yn      CHAR(1)       NULL,
    raw_json     NVARCHAR(MAX) NULL,
    collected_at DATE          NOT NULL,
    CONSTRAINT pk_schoolinfo_move PRIMARY KEY (schul_code, pban_yr)
);
GO
SELECT j = (SELECT 전출입 = COUNT(*) FROM silver.schoolinfo_move FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
