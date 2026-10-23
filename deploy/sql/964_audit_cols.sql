SET NOCOUNT ON;
SELECT (SELECT 표 = s.name + '.' + t.name, 칸 = STRING_AGG(CAST(c.name AS NVARCHAR(MAX)), ',') WITHIN GROUP (ORDER BY c.column_id)
          FROM sys.tables t JOIN sys.schemas s ON s.schema_id = t.schema_id JOIN sys.columns c ON c.object_id = t.object_id
         WHERE s.name + '.' + t.name IN ('silver.bld_basis_outline','silver.bld_title','silver.bld_expos','silver.bld_closed_title','silver.bld_closed_detail_done',
           'gold.closed_site','silver.rtms_trade','silver.kapt_complex','gold.complex_kapt','silver.applyhome_pblanc','gold.applyhome_link','silver.ned_aphus_done',
           'silver.ned_aphus_price','gold.complex','silver.cadastral_parcel','silver.land_char','silver.redev_zone','silver.arch_permit','silver.land_use_done',
           'silver.vworld_zone_done','silver.land_move_done','silver.building_footprint','silver.bld_hsprc','silver.juso_addr_done','gold.complex_pnu','silver.school','silver.subway_station','silver.kapt_cost')
         GROUP BY s.name, t.name FOR JSON PATH) AS j;
