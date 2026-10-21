/* 검색이 7~9초다. 원인 후보 둘을 가른다:
     (가) gold.complex(538,377행) 스캔 자체가 느리다 — 적재가 IO 를 먹는 중이다
     (나) 스칼라 UDF meta.fn_pnu_to_jibun 이 행마다 돈다
   ★ 같은 것을 **두 번** 돌려 데워지는지 본다(캐시 효과면 IO 다).
   ★ UDF 를 뺀 것과 넣은 것을 나란히 잰다. */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @q NVARCHAR(200) = N'%센트라스%';
SELECT 변형='A 1회차 COUNT', 행 = COUNT(*) FROM gold.complex c
 WHERE c.complex_nm LIKE @q OR c.rep_plat_plc LIKE @q OR c.rep_road_addr LIKE @q;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @q2 NVARCHAR(200) = N'%센트라스%';
SELECT 변형='B 2회차 같은 것', 행 = COUNT(*) FROM gold.complex c
 WHERE c.complex_nm LIKE @q2 OR c.rep_plat_plc LIKE @q2 OR c.rep_road_addr LIKE @q2;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @q3 NVARCHAR(200) = N'%센트라스%';
SELECT 변형='C 뷰로(UDF 포함 칸까지)', 행 = COUNT(*), 지번 = MAX(v.rep_jibun)
  FROM gold.v_complex_map v
 WHERE v.complex_nm LIKE @q3 OR v.rep_plat_plc LIKE @q3 OR v.rep_road_addr LIKE @q3;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* D — complex_nm 하나만 (칸 하나면 색인이 있나) */
DECLARE @q4 NVARCHAR(200) = N'%센트라스%';
SELECT 변형='D 이름만', 행 = COUNT(*) FROM gold.complex c WHERE c.complex_nm LIKE @q4;
