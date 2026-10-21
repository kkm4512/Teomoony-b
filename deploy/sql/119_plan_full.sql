USE Teomoony;
GO
SET NOCOUNT ON;
GO
DECLARE @d NVARCHAR(MAX) = (SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID('meta.v_load_plan'));
DECLARE @i INT = 1;
WHILE @i <= LEN(@d) BEGIN PRINT SUBSTRING(@d, @i, 180); SET @i = @i + 180; END
GO
