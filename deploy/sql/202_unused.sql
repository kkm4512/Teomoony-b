/* 적재는 했는데 화면이 안 쓰는 축 (2026-10-19)
   "더 붙일 데이터" 를 묻기 전에, **이미 받아놓고 안 보여주는 것**부터 센다.
   새 API 신청도 적재도 필요 없으니 가장 싸다. */
SET NOCOUNT ON;
SELECT 축 = '지역지구(bld_jijigu)',        건수 = COUNT(*) FROM silver.bld_jijigu
UNION ALL SELECT '토지특성(land_char)',          COUNT(*) FROM silver.land_char WHERE is_current = 1
/* ★ 2026-10-21: 등기(silver.registry_property) 줄을 뺐다 — 그 표는 ddl-bg 가 지웠다.
   없는 표 하나가 **애드혹 배치 전체를 500 으로 만든다**(SQL Server 는 배치를 통째로
   컴파일한다). health 에서 같은 일을 겪고도 여기를 놓쳤다. */
UNION ALL SELECT '인허가 동별 — 아직 화면에 안 씀', COUNT(*) FROM silver.arch_permit_dong
UNION ALL SELECT '주택가격(bld_hsprc)',          COUNT(*) FROM silver.bld_hsprc
UNION ALL SELECT '전유공용면적(bld_expos_pubuse_area)', COUNT(*) FROM silver.bld_expos_pubuse_area
UNION ALL SELECT '부속지번(bld_atch_jibun)',     COUNT(*) FROM silver.bld_atch_jibun;

/* 토지특성이 실제로 뭘 들고 있나 - 컬럼을 봐야 쓸 만한지 안다 */
SELECT TOP 3 * FROM silver.land_char WHERE is_current = 1;
