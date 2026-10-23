/* 11-249 일곱째 길 넣은 뒤 다시 잇기 — 290 의 프로시저를 다시 만든 뒤 실행 */
SET NOCOUNT ON;
SELECT j = (SELECT 전 = COUNT(*) FROM gold.applyhome_link FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
GO
EXEC gold.usp_refresh_applyhome_link;
GO
SELECT j = (SELECT 후 = (SELECT COUNT(*) FROM gold.applyhome_link),
  형제길 = (SELECT p.house_nm, l.complex_id, l.kapt_code FROM gold.applyhome_link l JOIN silver.applyhome_pblanc p ON p.house_manage_no = l.house_manage_no AND p.pblanc_no = l.pblanc_no
             WHERE l.근거 LIKE N'같은 공고 지번의 다른 공고%' ORDER BY p.pnu, p.rcrit_pblanc_de FOR JSON PATH)
  FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
