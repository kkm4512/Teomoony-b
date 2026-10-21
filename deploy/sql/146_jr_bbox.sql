USE Teomoony;
GO
SET NOCOUNT ON;
GO
SELECT CAST(MIN(bbox_minx) AS DECIMAL(12,7)) AS minx,
       CAST(MIN(bbox_miny) AS DECIMAL(12,7)) AS miny,
       CAST(MAX(bbox_maxx) AS DECIMAL(12,7)) AS maxx,
       CAST(MAX(bbox_maxy) AS DECIMAL(12,7)) AS maxy
  FROM silver.cadastral_parcel WHERE is_current=1 AND LEFT(pnu,10)='1129013300';
GO
