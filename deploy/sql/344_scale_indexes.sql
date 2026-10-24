/* 2026-10-24 전국 넓히기 전 진단 ② — 색인. 근거는 짐작이 아니라 SQL Server 의 '빠진 색인' 기록(실제로 돈 쿼리의 seek 수 × 효과)과
   공간 칸에 공간 색인이 없는 표(법정동 경계 · 정비구역 · 용도지역). 지금은 서울·안양이라 버티지만 전국(법정동 경계 474 → 약 2만)이면
   점 → 법정동 찾기(범위표 · 학교 잇기)가 줄마다 표 전체를 훑는다.
   ★ ONLINE 으로 만든다 — 화면 · 적재가 쓰는 중에도 막지 않는다. 이미 있으면 건너뛴다(다시 돌려도 된다). */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON; SET ANSI_NULLS ON; SET ANSI_PADDING ON; SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;
GO
/* 공간 색인 — 대한민국 경위도 범위(경도 124~132 · 위도 33~39.5). geometry 칸(SRID 4326 값을 평면으로 담음) */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('silver.lawd_boundary') AND name = 'six_lawd_boundary_geom')
    CREATE SPATIAL INDEX six_lawd_boundary_geom ON silver.lawd_boundary (geom) USING GEOMETRY_AUTO_GRID WITH (BOUNDING_BOX = (124, 33, 132, 39.5));
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('silver.lawd_boundary') AND name = 'ix_lawd_boundary_bbox')
    CREATE INDEX ix_lawd_boundary_bbox ON silver.lawd_boundary (is_current, bbox_minx, bbox_maxx) INCLUDE (bbox_miny, bbox_maxy, lawd_cd) WITH (ONLINE = ON);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('silver.redev_zone') AND name = 'six_redev_zone_geom')
    CREATE SPATIAL INDEX six_redev_zone_geom ON silver.redev_zone (geom) USING GEOMETRY_AUTO_GRID WITH (BOUNDING_BOX = (124, 33, 132, 39.5));
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('silver.land_use_zone') AND name = 'six_land_use_zone_geom')
    CREATE SPATIAL INDEX six_land_use_zone_geom ON silver.land_use_zone (geom) USING GEOMETRY_AUTO_GRID WITH (BOUNDING_BOX = (124, 33, 132, 39.5));
GO
/* 빠진 색인 기록 상위(seek × 효과) */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('silver.rtms_trade') AND name = 'ix_rtms_complex_amt')
    CREATE INDEX ix_rtms_complex_amt ON silver.rtms_trade (match_complex_id, is_rent, deal_amount)
        INCLUDE (trade_kind, deal_ymd, exclu_use_ar, floor_no, is_canceled) WITH (ONLINE = ON, SORT_IN_TEMPDB = ON);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('silver.vworld_zone') AND name = 'ix_vworld_zone_layer_key')
    CREATE INDEX ix_vworld_zone_layer_key ON silver.vworld_zone (layer, zone_key) INCLUDE (is_current) WITH (ONLINE = ON);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('meta.lawd_code') AND name = 'ix_lawd_code_names')
    CREATE INDEX ix_lawd_code_names ON meta.lawd_code (emd_nm, ri_nm, is_abolished) INCLUDE (sgg_nm, sgg_cd, sido_nm, lawd_cd, full_nm);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('silver.arch_permit') AND name = 'ix_arch_permit_gb')
    CREATE INDEX ix_arch_permit_gb ON silver.arch_permit (arch_gb_nm, is_current, hhld_cnt) INCLUDE (mgm_pmsrgst_pk, pnu, sigungu_cd, bjdong_cd) WITH (ONLINE = ON);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('meta.ingest_run') AND name = 'ix_ingest_run_scope')
    CREATE INDEX ix_ingest_run_scope ON meta.ingest_run (scope_key) INCLUDE (status, source_id) WITH (ONLINE = ON);
GO
SELECT 표 = OBJECT_SCHEMA_NAME(object_id) + '.' + OBJECT_NAME(object_id), name FROM sys.indexes
 WHERE name IN ('six_lawd_boundary_geom','ix_lawd_boundary_bbox','six_redev_zone_geom','six_land_use_zone_geom','ix_rtms_complex_amt','ix_vworld_zone_layer_key','ix_lawd_code_names','ix_arch_permit_gb','ix_ingest_run_scope');
