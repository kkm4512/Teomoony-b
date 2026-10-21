/* ============================================================
   217_land_char_index : 토지특성 적재용 인덱스 (2026-10-20)

   ★ 왜: load_land_char.py 는 필지마다 (pnu, base_year) 로 **두 번** 찾는다
     (SCD2 의 UPDATE 와 IF NOT EXISTS). 인덱스가 없으면 행이 쌓일수록
     그 두 번이 전부 전체 훑기가 된다 — 90만 필지 × 14년이면 끝나지 않는다.
   ★ 지금 land_char 은 3행이다. 지금 만들면 공짜다. **적재 전에 만든다.**
   ★ 필터드가 아니라 일반 인덱스로 둔다. is_current 를 키에 넣어
     '현재행만' 조건을 그대로 태운다(211 에서 필터 칸을 키에서 빼먹어 당했다).
   ★ silver.cadastral_parcel(필지 적재 중)·bld_*(앞줄 적재 중)은 손대지 않는다.
   ============================================================ */
USE Teomoony;
GO
SET NOCOUNT ON;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes
                WHERE name = 'ix_land_char_key' AND object_id = OBJECT_ID('silver.land_char'))
BEGIN
  CREATE INDEX ix_land_char_key
      ON silver.land_char (pnu, base_year, is_current)
      INCLUDE (row_hash);
  PRINT '  ix_land_char_key 만듦';
END
ELSE PRINT '  ix_land_char_key 이미 있음';
GO
/* 화면은 '그 필지의 최신 연도' 를 찾는다 — 그 길도 깔아 둔다 */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
                WHERE name = 'ix_land_char_cur' AND object_id = OBJECT_ID('silver.land_char'))
BEGIN
  CREATE INDEX ix_land_char_cur
      ON silver.land_char (pnu, is_current, base_year DESC)
      INCLUDE (pblntf_pclnd, lndpcl_ar, prpos_area1_nm, lndcgr_nm);
  PRINT '  ix_land_char_cur 만듦';
END
ELSE PRINT '  ix_land_char_cur 이미 있음';
GO
SELECT i.name, i.type_desc,
       칸 = STUFF((SELECT ', ' + c.name FROM sys.index_columns ic
                     JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
                    WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id
                      AND ic.is_included_column = 0
                    ORDER BY ic.key_ordinal FOR XML PATH('')), 1, 2, '')
  FROM sys.indexes i WHERE i.object_id = OBJECT_ID('silver.land_char') AND i.index_id > 0
 ORDER BY i.index_id;
GO
