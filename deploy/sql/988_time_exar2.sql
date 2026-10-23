SET NOCOUNT ON; SET ARITHABORT OFF;
DECLARE @t DATETIME2 = SYSDATETIME();
EXEC sp_executesql N'DECLARE @h TABLE (pk VARCHAR(50) PRIMARY KEY);
INSERT INTO @h SELECT DISTINCT h.호PK FROM gold.v_complex_ho h WHERE h.complex_id = @id AND h.호PK IS NOT NULL;
SELECT 잰호 = SUM(CASE WHEN x.전유 > 0 AND x.공용 > 0 THEN 1 ELSE 0 END), 면적행있는호 = COUNT(*)
  FROM @h h CROSS APPLY (SELECT 전유 = SUM(CASE WHEN a.expos_pubuse_gb_cd = ''1'' THEN a.area END), 공용 = SUM(CASE WHEN a.expos_pubuse_gb_cd = ''2'' THEN a.area END)
                           FROM silver.bld_expos_pubuse_area a WHERE a.mgm_bldrgst_pk = h.pk AND a.is_current = 1) x
 WHERE (x.전유 > 0 OR x.공용 > 0)', N'@id int', @id = 469943;
SELECT ms = DATEDIFF(MILLISECOND, @t, SYSDATETIME());
