SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT j = (SELECT c.name FROM sys.columns c WHERE c.object_id = OBJECT_ID('silver.school_zone') FOR JSON PATH);
GO
SELECT j = (SELECT COUNT(*) FROM silver.school_zone);
