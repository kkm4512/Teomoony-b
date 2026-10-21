USE Teomoony;
GO
SET NOCOUNT ON;
GO
SELECT lawd = LEFT(pnu,10),
       minx=MIN(bbox_minx), miny=MIN(bbox_miny), maxx=MAX(bbox_maxx), maxy=MAX(bbox_maxy),
       폭도 = MAX(bbox_maxx)-MIN(bbox_minx), 높이도 = MAX(bbox_maxy)-MIN(bbox_miny),
       필지 = COUNT(*)
  FROM silver.cadastral_parcel
 WHERE is_current=1 AND LEFT(pnu,10) IN ('1129013300','1129013400','1129013900','1129010100')
 GROUP BY LEFT(pnu,10) ORDER BY 폭도 DESC;
GO
