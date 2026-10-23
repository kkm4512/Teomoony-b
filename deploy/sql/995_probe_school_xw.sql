SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT j = (SELECT c.name, t = TYPE_NAME(c.user_type_id) FROM sys.columns c WHERE c.object_id = OBJECT_ID('silver.lawd_boundary') FOR JSON PATH);
GO
SELECT j = (SELECT TOP 5 school_id, school_nm, fond_date, lat, lon FROM silver.school WHERE is_current = 1 AND lnmadr LIKE N'서울특별시 종로구%' FOR JSON PATH);
