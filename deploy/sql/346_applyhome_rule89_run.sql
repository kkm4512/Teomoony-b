/* 11-264 여덟째(정비계획 다리) · 아홉째(세대 같음) 넣은 뒤 다시 잇기 — 290 의 프로시저를 다시 만든 뒤 실행 */
SET NOCOUNT ON;
EXEC gold.usp_refresh_applyhome_link;
GO
SELECT j = (SELECT 근거, n = COUNT(*) FROM gold.applyhome_link GROUP BY 근거 ORDER BY n DESC FOR JSON PATH);
SELECT j = (SELECT p.house_nm, 단지 = c.complex_nm, c.hhld_cnt_sum, l.근거 FROM gold.applyhome_link l JOIN silver.applyhome_pblanc p ON p.house_manage_no = l.house_manage_no AND p.pblanc_no = l.pblanc_no
             LEFT JOIN gold.complex c ON c.complex_id = l.complex_id WHERE l.근거 LIKE N'사업 전 지번%' ORDER BY l.근거, p.house_nm FOR JSON PATH);
