SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @p geometry;
SELECT j = (SELECT
  안 = (SELECT COUNT(*) FROM silver.lawd_boundary lb WHERE lb.lawd_cd = '1129013800' AND lb.is_current = 1
          AND lb.geom.STIntersects(geometry::Point(127.04608100, 37.61002442, lb.geom.STSrid)) = 1),
  경계수 = (SELECT COUNT(*) FROM silver.lawd_boundary WHERE lawd_cd = '1129013800'),
  현행경계수 = (SELECT COUNT(*) FROM silver.lawd_boundary WHERE lawd_cd = '1129013800' AND is_current = 1),
  같은날알리미 = (SELECT schul_code, schul_nm, adrcd_cd FROM silver.schoolinfo WHERE knd_code = '02' AND (fond_ymd IN ('19720714','19710901') OR JSON_VALUE(raw_json,'$.FOAS_MEMRD') IN ('19720714','19710901')) FOR JSON PATH),
  같은날우리 = (SELECT school_id, school_nm, lnmadr FROM silver.school WHERE is_current = 1 AND school_se = N'초등학교' AND REPLACE(fond_date,'-','') IN ('19720714','19710901') FOR JSON PATH)
  FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
