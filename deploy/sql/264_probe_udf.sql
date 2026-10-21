/* 검색 6.5초의 범인은 스칼라 UDF meta.fn_pnu_to_jibun (263 에서 쟀다: 표 1.0초 → 뷰 6.5초).
   다중 문장(IF·DECLARE)이라 **인라인이 안 된다** → 행마다 호출되고 계획이 직렬이 된다.

   ★ 고치는 법은 **함수를 한 문장으로 바꾸는 것**이다. 뷰에 식을 풀어 쓰면 빨라지지만
     같은 로직이 두 군데가 된다(작업방식 10장) — 그러면 안 된다. 함수를 고친다.
   ★ 먼저 **호환 수준**을 본다. 스칼라 UDF 인라이닝은 150 이상에서만 돈다.
   ★ 그리고 시험용 함수를 만들어 **538,377행 전수로 결과를 맞춰 본다.** 빨라도 다르면 못 쓴다. */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 호환수준 = compatibility_level, 이름 = name FROM sys.databases WHERE database_id = DB_ID();
GO
IF OBJECT_ID('meta.fn_pnu_to_jibun2') IS NOT NULL DROP FUNCTION meta.fn_pnu_to_jibun2;
GO
/* 지금 함수와 **글자 그대로 같은 규칙**을 한 문장으로 */
CREATE FUNCTION meta.fn_pnu_to_jibun2 (@pnu CHAR(19))
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
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* 전수 대조 — EXCEPT 로 양쪽. `=` 는 NULL 때문에 전부 '다름' 이 된다(229 에서 겪음). */
SELECT 다른건수 = (
  SELECT COUNT(*) FROM (
    SELECT rep_pnu, meta.fn_pnu_to_jibun(rep_pnu) AS a FROM gold.complex
    EXCEPT
    SELECT rep_pnu, meta.fn_pnu_to_jibun2(rep_pnu) FROM gold.complex
  ) x
), 전체 = (SELECT COUNT(*) FROM gold.complex);
