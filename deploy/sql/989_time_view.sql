SET NOCOUNT ON; SET ARITHABORT OFF;
DECLARE @t DATETIME2 = SYSDATETIME(), @a INT, @b INT, @c INT;
EXEC sp_executesql N'IF OBJECT_ID(''tempdb..#hx'') IS NOT NULL DROP TABLE #hx; SELECT DISTINCT 호PK INTO #hx FROM gold.v_complex_ho WHERE complex_id = @id AND 호PK IS NOT NULL OPTION (MAXDOP 1);', N'@id int', @id = 528197;
SET @a = DATEDIFF(MILLISECOND, @t, SYSDATETIME()); SET @t = SYSDATETIME();
EXEC sp_executesql N'DECLARE @h TABLE (pk VARCHAR(50) PRIMARY KEY); INSERT INTO @h SELECT DISTINCT h.호PK FROM gold.v_complex_ho h WHERE h.complex_id = @id AND h.호PK IS NOT NULL;', N'@id int', @id = 528197;
SET @b = DATEDIFF(MILLISECOND, @t, SYSDATETIME()); SET @t = SYSDATETIME();
DECLARE @n INT; SELECT @n = COUNT(*) FROM gold.v_complex_ho WHERE complex_id = 528197;
SET @c = DATEDIFF(MILLISECOND, @t, SYSDATETIME());
SELECT j = (SELECT selectinto_ms = @a, tablevar_ms = @b, literal_ms = @c, 호 = @n FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
