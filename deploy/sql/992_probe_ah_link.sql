SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT j = (SELECT l.house_manage_no, l.pblanc_no, l.complex_id, l.kapt_code, l.근거, p.pnu
  FROM gold.applyhome_link l JOIN silver.applyhome_pblanc p ON p.house_manage_no = l.house_manage_no AND p.pblanc_no = l.pblanc_no
 WHERE p.pnu IN ('1121510300105920039', '1135010500106900000') FOR JSON PATH);
