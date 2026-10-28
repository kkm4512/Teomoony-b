SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT TOP 25 k.kapt_name, p.kapt_세대, c.complex_nm, p.대장_세대, p.사용승인, c.rep_plat_plc
  FROM gold.kapt_pnu_link p JOIN silver.kapt_complex k ON k.kapt_code = p.kapt_code AND k.is_current = 1 JOIN gold.complex c ON c.complex_id = p.complex_id ORDER BY NEWID();
/* 이름이 한 글자도 안 겹치는 것(눈으로 볼 것만 고르기 — 판단에는 안 씀) */
SELECT 이름안겹침 = SUM(CASE WHEN c.complex_nm LIKE N'%번지' THEN 0 WHEN CHARINDEX(LEFT(REPLACE(k.kapt_name, ' ', ''), 2), REPLACE(c.complex_nm, ' ', '')) = 0 THEN 1 ELSE 0 END),
       주소꼴이름 = SUM(CASE WHEN c.complex_nm LIKE N'%번지' THEN 1 ELSE 0 END), 전체 = COUNT(*)
  FROM gold.kapt_pnu_link p JOIN silver.kapt_complex k ON k.kapt_code = p.kapt_code AND k.is_current = 1 JOIN gold.complex c ON c.complex_id = p.complex_id;
SELECT TOP 15 k.kapt_name, p.kapt_세대, c.complex_nm, p.대장_세대, p.사용승인
  FROM gold.kapt_pnu_link p JOIN silver.kapt_complex k ON k.kapt_code = p.kapt_code AND k.is_current = 1 JOIN gold.complex c ON c.complex_id = p.complex_id
 WHERE c.complex_nm NOT LIKE N'%번지' AND CHARINDEX(LEFT(REPLACE(k.kapt_name, ' ', ''), 2), REPLACE(c.complex_nm, ' ', '')) = 0 ORDER BY NEWID();
