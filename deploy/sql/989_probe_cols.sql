SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT TOP 1 j = raw_json FROM silver.childcare WHERE 이름 = N'나리어린이집' AND is_current = 1;
