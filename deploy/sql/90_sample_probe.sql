SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* ============================================================
   90_sample_probe : 구조 검증용 합성 샘플
   ※ 실제 공공데이터가 아님. API 응답 "형태"만 모사해서
     단지코드 -> 4축 연계가 실제로 성립하는지 확인하는 용도.

   시나리오 (일부러 까다로운 케이스를 넣음)
     A) 아파트 단지 : 총괄표제부 1 + 표제부 3동, 2개 필지에 걸침
                      -> 단지 1개로 묶여야 하고 pnu_cnt=2 여야 함
     B) 단독 건물   : 총괄표제부 없음
                      -> 자기 자신이 단지 1개
     C) 산 지번 건물 : platGbCd=1
                      -> PNU 11번째 자리가 '2' 여야 함
     D) 토지 누락   : 필지 1개는 land_char 없음
                      -> land_coverage < 1.0 로 잡혀야 함
     E) 도로명키 결손 : 1동은 na_road_cd NULL
                      -> v_link_gap 에 ROADKEY_NULL 로 잡혀야 함
   ============================================================ */
USE Teomoony;
GO

/* 초기화 (재실행 가능하게) */
DELETE FROM gold.complex_pnu;
DELETE FROM gold.complex_bld;
DELETE FROM gold.complex_identity;
DELETE FROM gold.complex;
DELETE FROM silver.land_char;
DELETE FROM silver.road_addr;
DELETE FROM silver.bld_atch_jibun;
DELETE FROM silver.bld_recap_title;
DELETE FROM silver.bld_title;
DELETE FROM meta.lawd_code;
GO

/* ---------- 기준정보 ---------- */
INSERT INTO meta.lawd_code (lawd_cd, sido_nm, sgg_nm, emd_nm, full_nm) VALUES
 ('1111010100', N'서울특별시', N'종로구', N'청운동', N'서울특별시 종로구 청운동'),
 ('1111010200', N'서울특별시', N'종로구', N'신교동', N'서울특별시 종로구 신교동');
GO

/* ============================================================
   A) 아파트 단지 - 총괄표제부
   ============================================================ */
DECLARE @h BINARY(32) = HASHBYTES('SHA2_256','seed');

INSERT INTO silver.bld_recap_title
 (mgm_bldrgst_pk, sigungu_cd, bjdong_cd, plat_gb_cd, bun, ji, pnu,
  plat_plc, new_plat_plc, bld_nm, regstr_gb_cd, regstr_kind_cd,
  plat_area, arch_area, tot_area, main_bld_cnt, hhld_cnt, use_apr_day, crtn_day, row_hash)
VALUES
 ('11110-100000001','11110','10100','0','136','74',
  meta.fn_make_pnu('11110','10100','0','136','74'),
  N'서울특별시 종로구 청운동 136-74', N'서울특별시 종로구 자하문로 100',
  N'터무니샘플아파트', '2','3',
  12500.00, 3200.00, 48000.00, 3, 240, '20051130','20260901', @h);

/* 표제부 3동 - 모두 같은 총괄표제부를 가리킨다 */
INSERT INTO silver.bld_title
 (mgm_bldrgst_pk, mgm_up_bldrgst_pk, regstr_gb_cd, regstr_gb_nm, regstr_kind_cd, regstr_kind_nm,
  sigungu_cd, bjdong_cd, plat_gb_cd, bun, ji, pnu, plat_plc,
  na_road_cd, na_bjdong_cd, na_ugrnd_cd, na_main_bun, na_sub_bun, new_plat_plc,
  bld_nm, dong_nm, plat_area, arch_area, tot_area, hhld_cnt,
  grnd_flr_cnt, ugrnd_flr_cnt, main_purps_cd, main_purps_nm, strct_nm,
  use_apr_day, crtn_day, row_hash)
VALUES
 /* 101동 - 정상 */
 ('11110-100000011','11110-100000001','2',N'집합','2',N'표제부',
  '11110','10100','0','136','74', meta.fn_make_pnu('11110','10100','0','136','74'),
  N'서울특별시 종로구 청운동 136-74',
  '111104166999','10100','0',100,0, N'서울특별시 종로구 자하문로 100',
  N'터무니샘플아파트', N'101동', 12500.00, 1100.00, 16000.00, 80,
  15, 2, '02000', N'공동주택', N'철근콘크리트구조',
  '20051130','20260901', @h),
 /* 102동 - 정상 */
 ('11110-100000012','11110-100000001','2',N'집합','2',N'표제부',
  '11110','10100','0','136','74', meta.fn_make_pnu('11110','10100','0','136','74'),
  N'서울특별시 종로구 청운동 136-74',
  '111104166999','10100','0',100,0, N'서울특별시 종로구 자하문로 100',
  N'터무니샘플아파트', N'102동', 12500.00, 1100.00, 16000.00, 80,
  15, 2, '02000', N'공동주택', N'철근콘크리트구조',
  '20051130','20260901', @h),
 /* 103동 - E) 도로명 키 결손 (실제로 자주 발생) */
 ('11110-100000013','11110-100000001','2',N'집합','2',N'표제부',
  '11110','10100','0','136','74', meta.fn_make_pnu('11110','10100','0','136','74'),
  N'서울특별시 종로구 청운동 136-74',
  NULL, NULL, NULL, NULL, NULL, NULL,
  N'터무니샘플아파트', N'103동', 12500.00, 1000.00, 16000.00, 80,
  15, 2, '02000', N'공동주택', N'철근콘크리트구조',
  '20051130','20260901', @h),
 /* B) 단독 건물 - 총괄표제부 없음 */
 ('11110-200000021', NULL, '1',N'일반','1',N'일반',
  '11110','10200','0','55','3', meta.fn_make_pnu('11110','10200','0','55','3'),
  N'서울특별시 종로구 신교동 55-3',
  '111104166888','10200','0',22,0, N'서울특별시 종로구 필운대로 22',
  N'터무니상가', NULL, 480.00, 280.00, 1400.00, 0,
  5, 1, '14000', N'제2종근린생활시설', N'철근콘크리트구조',
  '19980415','20260901', @h),
 /* C) 산 지번 건물 - platGbCd = 1 */
 ('11110-300000031', NULL, '1',N'일반','1',N'일반',
  '11110','10200','1','15','1', meta.fn_make_pnu('11110','10200','1','15','1'),
  N'서울특별시 종로구 신교동 산 15-1',
  '111104166777','10200','0',7,0, N'서울특별시 종로구 옥인길 7',
  N'터무니산장', NULL, 900.00, 150.00, 300.00, 0,
  2, 0, '01000', N'단독주택', N'목구조',
  '20150620','20260901', @h);
GO

/* A) 부속지번 - 단지가 2번째 필지에 걸쳐 있음
   이게 없으면 단지-토지 연계가 대지 1필지로 뭉개진다 */
DECLARE @h2 BINARY(32) = HASHBYTES('SHA2_256','seed2');
INSERT INTO silver.bld_atch_jibun
 (mgm_bldrgst_pk, atch_sigungu_cd, atch_bjdong_cd, atch_plat_gb_cd, atch_bun, atch_ji,
  atch_pnu, plat_plc, crtn_day, row_hash)
VALUES
 ('11110-100000011','11110','10100','0','136','75',
  meta.fn_make_pnu('11110','10100','0','136','75'),
  N'서울특별시 종로구 청운동 136-75','20260901', @h2);
GO

/* ---------- 토지 (D: 136-75 는 일부러 누락) ---------- */
DECLARE @h3 BINARY(32) = HASHBYTES('SHA2_256','seed3');
INSERT INTO silver.land_char
 (pnu, base_year, mnnm_slno, lndcgr_code, lndcgr_nm, lndpcl_ar,
  prpos_area1_nm, lad_use_sittn_nm, road_side_code_nm, pblntf_pclnd, last_updt_dt, row_hash)
VALUES
 (meta.fn_make_pnu('11110','10100','0','136','74'),'2026', N'136-74','08',N'대', 11000.00,
  N'제2종일반주거지역', N'아파트', N'광대한면', 7850000.00,'20260101', @h3),
 (meta.fn_make_pnu('11110','10200','0','55','3'),  '2026', N'55-3', '08',N'대',   480.00,
  N'제1종일반주거지역', N'상업용',  N'소로한면',   9200000.00,'20260101', @h3),
 (meta.fn_make_pnu('11110','10200','1','15','1'),  '2026', N'산15-1','05',N'임야', 900.00,
  N'자연녹지지역',     N'단독주택', N'세로(불)',    310000.00,'20260101', @h3);
GO

/* ---------- 도로명주소 ---------- */
DECLARE @h4 BINARY(32) = HASHBYTES('SHA2_256','seed4');
INSERT INTO silver.road_addr
 (bld_mgt_no, road_cd, ugrnd_yn, bld_main_no, bld_sub_no, pnu, lawd_cd,
  road_nm, emd_nm, bld_nm, zip_no, road_addr_full, jibun_addr_full,
  is_representative, mvmn_de, mvmn_reason_cd, row_hash)
VALUES
 ('1111010100101360074000001','111104166999','0',100,0,
  meta.fn_make_pnu('11110','10100','0','136','74'),'1111010100',
  N'자하문로', N'청운동', N'터무니샘플아파트','03047',
  N'서울특별시 종로구 자하문로 100', N'서울특별시 종로구 청운동 136-74',
  1,'20260801','31', @h4),
 ('1111010200100550003000001','111104166888','0',22,0,
  meta.fn_make_pnu('11110','10200','0','55','3'),'1111010200',
  N'필운대로', N'신교동', N'터무니상가','03044',
  N'서울특별시 종로구 필운대로 22', N'서울특별시 종로구 신교동 55-3',
  1,'20260801','31', @h4),
 ('1111010200200150001000001','111104166777','0',7,0,
  meta.fn_make_pnu('11110','10200','1','15','1'),'1111010200',
  N'옥인길', N'신교동', N'터무니산장','03043',
  N'서울특별시 종로구 옥인길 7', N'서울특별시 종로구 신교동 산 15-1',
  1,'20260801','31', @h4);
GO

/* ============================================================
   단지 자동 구성 실행
   ============================================================ */
EXEC gold.usp_build_complexes @sigungu_cd = '11110';
GO

PRINT '90_sample_probe done.';
GO
