SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT (SELECT TOP 5 road_addr, jibun_addr, rn_mgt_sn, buld_mnnm, buld_slno, udrt_yn, pnu FROM silver.juso_addr WHERE road_addr LIKE N'%고덕로80길%' FOR JSON PATH) AS a,
       (SELECT TOP 5 new_plat_plc, pnu, 이름 FROM gold.closed_site WHERE lat IS NULL AND new_plat_plc LIKE N'%고덕로%' FOR JSON PATH) AS b;
