/* ============================================================
   216_complex_geo_index : gold.complex 좌표 인덱스 (2026-10-20)

   ★ 왜: "내 위치 근처 단지" 를 만들려고 보니 `gold.complex` 에 좌표
     인덱스가 **하나도 없었다.** 지금 `/api/complexes/markers` 는 bbox 로
     거르는데, 538,377 행을 매번 전부 훑고 있다(374ms 의 정체).
     근처 단지도 같은 칸(centroid_lng, centroid_lat)을 쓴다 — 한 번 만들면 둘이 같이 빨라진다.

   ★ 키 순서: 경도 먼저. 06_cadastral.sql 의 ix_parcel_centroid 와 같은 순서로
     맞춘다 — 같은 모양의 질의를 다른 순서로 세워 두면 나중에 비교가 안 된다.

   ★ 필터드 인덱스로 만들면서 **필터에 쓴 칸을 키에 넣는다.**
     211 에서 `WHERE match_pnu IS NOT NULL` 인데 `match_complex_id` 를 키에서
     빼먹어 본문을 다시 읽느라 **더 느려졌다**(724ms -> 1,463ms). 여기서는
     필터가 `centroid_lat IS NOT NULL` 이고 centroid_lat 이 키에 있다. 괜찮다.

   ★ 결과를 바꿀 수 없다 — 찾아가는 길만 바꾼다.

   ★ gold.complex 는 지금 적재 중이 아니다(필지 적재기가 끝날 때
     usp_refresh_complex_geo 를 돌린다). DDL 은 스키마 잠금을 잡으므로
     그 갱신과 겹치면 잠깐 기다린다 — 213 때도 같았고 문제없었다.
     ★ silver.cadastral_parcel(필지 적재 중)·silver.bld_*(앞줄 적재 중)은
       **손대지 않는다.**
   ============================================================ */
USE Teomoony;
GO
SET NOCOUNT ON;
GO

IF EXISTS (SELECT 1 FROM sys.indexes
            WHERE name = 'ix_complex_centroid' AND object_id = OBJECT_ID('gold.complex'))
BEGIN
  PRINT '  ix_complex_centroid 이미 있음 — 건너뜀';
END
ELSE
BEGIN
  CREATE INDEX ix_complex_centroid
      ON gold.complex (centroid_lng, centroid_lat)
      INCLUDE (complex_id, complex_nm, dong_cnt, hhld_cnt_sum, pnu_cnt,
               sigungu_cd, bjdong_cd, rep_pnu, has_recap)
      WHERE centroid_lat IS NOT NULL;
  PRINT '  ix_complex_centroid 만듦';
END
GO

PRINT '--- gold.complex 인덱스 목록 ---';
SELECT i.name, i.type_desc, i.has_filter, i.filter_definition,
       칸 = STUFF((SELECT ', ' + c.name
                     FROM sys.index_columns ic
                     JOIN sys.columns c ON c.object_id = ic.object_id
                                       AND c.column_id = ic.column_id
                    WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id
                      AND ic.is_included_column = 0
                    ORDER BY ic.key_ordinal
                    FOR XML PATH('')), 1, 2, '')
  FROM sys.indexes i
 WHERE i.object_id = OBJECT_ID('gold.complex') AND i.index_id > 0
 ORDER BY i.index_id;
GO
