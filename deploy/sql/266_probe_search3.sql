/* UDF 를 고친 뒤 '센트라스' 2.2초 · '대조동 14-45' 1.7초인데 **'석관' 은 17초**다.
   차이: '석관' 은 **법정동 이름에 걸린다**(석관동). 검색 엔드포인트는 단지 말고
   법정동도 같이 찾는데, 그게 11-120 의 **무거운 뷰 gold.v_lawd_map** 이다.
   → 가설: 법정동이 하나라도 걸리면 그 뷰의 OUTER APPLY(법정동당 1.4초)가 돈다.
   ★ 재서 가른다. 맞다면 11-120 의 덮는 색인 하나가 **법정동 지도와 검색을 같이** 고친다. */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @q NVARCHAR(200) = N'%석관%';
SELECT 변형='A 단지만(석관)', 행=COUNT(*)
  FROM gold.v_complex_map v
 WHERE v.complex_nm LIKE @q OR v.rep_plat_plc LIKE @q OR v.rep_road_addr LIKE @q;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @q2 NVARCHAR(200) = N'%석관%';
SELECT 변형='B 법정동 검색(석관)', 행=COUNT(*)
  FROM (SELECT TOP 8 lawd_cd, complex_cnt, trade_cnt, max_amount
          FROM gold.v_lawd_map
         WHERE emd_nm LIKE @q2 OR full_nm LIKE @q2 OR lawd_cd LIKE @q2
         ORDER BY complex_cnt DESC, emd_nm) y;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @q3 NVARCHAR(200) = N'%석관%';
SELECT 변형='C 법정동 — 무거운 칸 빼고', 행=COUNT(*)
  FROM (SELECT TOP 8 lawd_cd, emd_nm
          FROM gold.v_lawd_map
         WHERE emd_nm LIKE @q3 OR full_nm LIKE @q3 OR lawd_cd LIKE @q3
         ORDER BY emd_nm) y;
