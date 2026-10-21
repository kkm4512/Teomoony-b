SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* ============================================================
   24_flr_outline : 층별개요 적재 준비 (2026-10-16)

   `silver.bld_flr_outline` 은 02_silver.sql 이래로 **스키마만 있고 0건**이었다.
   적재기 OPS 에 오퍼레이션조차 등록돼 있지 않았다(README 11장의 열린 항목).

   2026-10-16 probe 로 확정한 것 (돈암동 636번지, 305건):

   ★ 응답 철자가 `areaExctYn` 이다. `areaExclYn`(Excl) 이 아니다.
     기대 필드명으로 매핑하면 **영영 NULL 로 남는다.** hoCnt/kaptdaCnt 와 같은 종류.

   ★ `dongNm` 이 온다. 동별 표제부와 조인하지 않아도 동을 안다.
     `mainAtchGbCd` 로 주/부속도 갈린다 (지하주차장·교회가 부속건축물).

   ★ **자연키가 유일하지 않다.** 같은 동·층·용도·구조·주부속인데 면적만 다른
     행이 실제로 온다 — 지하주차장 지하2층 아파트 283.2 / 264.5.
     같은 층이 여러 구획으로 기재된 것이다.

     키에 area 를 넣으면 면적 정정 시 옛 행이 안 닫혀 고아가 되고,
     rnum 을 쓰면 구획 하나가 늘 때 뒤가 전부 밀려 거짓 변경이 쏟아진다.
     -> **적재기가 합친다**(`collapse_rows`). 면적은 더하고 구획 수는 `seg_cnt` 에 남긴다.
        원본은 bronze.api_payload 에 그대로 있으므로 되돌릴 수 있다.

   ★ 호는 여기 없다. `ho_nm` 을 가진 테이블은 silver.bld_expos_pubuse_area 뿐이고
     그것은 적재하지 않기로 한 축이다(정책.md 4장). **이 축은 층까지다.**
   ============================================================ */
USE Teomoony;
GO

IF COL_LENGTH('silver.bld_flr_outline','dong_nm') IS NULL
ALTER TABLE silver.bld_flr_outline ADD
    dong_nm          NVARCHAR(100) NULL,      -- dongNm        '106동' / '지하주차장' / '교회'
    bld_nm           NVARCHAR(200) NULL,      -- bldNm
    main_atch_gb_cd  VARCHAR(2)    NULL,      -- mainAtchGbCd  0 주건축물 / 1 부속건축물
    main_atch_gb_nm  NVARCHAR(40)  NULL,
    seg_cnt          INT           NULL;      -- 합쳐진 구획 수. 1 이면 원본 그대로
GO

/* 현재행 유일성. collapse 를 거친 뒤라야 성립한다 —
   합치지 않고 넣으면 이 인덱스가 바로 터진다. 그게 의도다:
   **조용히 중복이 쌓이느니 적재가 멈추는 편이 낫다.** */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='uq_bld_flr_current')
CREATE UNIQUE INDEX uq_bld_flr_current ON silver.bld_flr_outline
    (mgm_bldrgst_pk, flr_gb_cd, flr_no, main_purps_cd, strct_cd, main_atch_gb_cd)
    WHERE is_current = 1;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_bld_flr_dong')
CREATE INDEX ix_bld_flr_dong ON silver.bld_flr_outline (dong_nm) WHERE is_current = 1;
GO

/* ---------- 동 x 층 격자 ----------
   화면이 쓰는 뷰. 한 동의 한 층에 용도가 여럿이면 행도 여럿이다 — 합치지 않는다.
   "1층 = 근린생활 + 주차장" 은 뭉개면 안 되는 사실이다. */
IF OBJECT_ID('gold.v_complex_floor') IS NOT NULL DROP VIEW gold.v_complex_floor;
GO
CREATE VIEW gold.v_complex_floor
AS
SELECT cb.complex_id,
       f.mgm_bldrgst_pk,
       동 = COALESCE(NULLIF(f.dong_nm,''), NULLIF(f.bld_nm,''), t.dong_nm),
       주부속 = f.main_atch_gb_nm,
       층구분 = f.flr_gb_nm,
       /* 지하를 음수로 둔다. 정렬 한 번으로 지하->지상이 떨어진다 */
       층 = CASE WHEN f.flr_gb_cd = '10' THEN -f.flr_no ELSE f.flr_no END,
       층명 = f.flr_no_nm,
       용도 = f.main_purps_nm,
       기타용도 = f.etc_purps,
       구조 = f.strct_nm,
       면적 = f.area,
       구획수 = f.seg_cnt
FROM gold.complex_bld cb
JOIN silver.bld_flr_outline f
  ON f.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND f.is_current = 1
LEFT JOIN silver.bld_title t
  ON t.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND t.is_current = 1;
GO

PRINT '24_flr_outline done.';
GO
