/* 새 함수(한 문장)가 실제로 빠른가. 264 에서 결과는 전수 동일(다른건수 0/538,377)임을 확인했다. */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @q NVARCHAR(200) = N'%센트라스%';
SELECT 변형='지금 함수(다중문장)', 행=COUNT(*), 지번=MAX(meta.fn_pnu_to_jibun(c.rep_pnu))
  FROM gold.complex c
 WHERE c.complex_nm LIKE @q OR c.rep_plat_plc LIKE @q OR c.rep_road_addr LIKE @q;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @q2 NVARCHAR(200) = N'%센트라스%';
SELECT 변형='새 함수(한문장)', 행=COUNT(*), 지번=MAX(meta.fn_pnu_to_jibun2(c.rep_pnu))
  FROM gold.complex c
 WHERE c.complex_nm LIKE @q2 OR c.rep_plat_plc LIKE @q2 OR c.rep_road_addr LIKE @q2;
