USE Teomoony;
GO
SET NOCOUNT ON;
GO
DECLARE @d NVARCHAR(MAX)=(SELECT definition FROM sys.sql_modules WHERE object_id=OBJECT_ID('gold.v_complex_ho_price'));
DECLARE @i INT=1;
WHILE @i<=LEN(@d) BEGIN PRINT SUBSTRING(@d,@i,170); SET @i=@i+170; END
GO
PRINT '--- bld_hsprc 규모 ---';
SELECT 전체=COUNT(*), 현재=SUM(CASE WHEN is_current=1 THEN 1 ELSE 0 END) FROM silver.bld_hsprc;
GO
