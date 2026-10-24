/* 2026-10-24 10:44 사장님 "어린이집 유치원 상권도 자세히 볼 데이터가 있으면 받아오고 모달로" — 유치원알리미 공시 항목 원문 그대로.
   항목(item) = API 이름: basicInfo2 일반현황 · building 건물 · classArea 교실면적 · teachersInfo 직위·자격별 교직원 · yearOfWork 근속연수 ·
   lessonDay 수업일수 · schoolBus 통학차량 · safetyEdu 안전점검 · schoolMeal 급식 · environmentHygiene 환경위생 · afterSchoolPresent 방과후 과정.
   칸 정의는 유치원알리미 OPENAPI 각 항목 페이지(출력항목)를 따른다 — 화면이 원문 칸 이름으로 읽는다. 대표자 · 원장 이름은 화면에 안 쓴다. */
IF OBJECT_ID('silver.kinder_info') IS NULL
CREATE TABLE silver.kinder_info (
    kinder_cd    VARCHAR(64)   NOT NULL,
    item         VARCHAR(30)   NOT NULL,
    pbnt_tmng    VARCHAR(10)   NULL,
    raw_json     NVARCHAR(MAX) NOT NULL,
    collected_at DATE          NOT NULL,
    CONSTRAINT pk_kinder_info PRIMARY KEY (kinder_cd, item)
);
GO
SELECT j = (SELECT n = COUNT(*) FROM silver.kinder_info FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
