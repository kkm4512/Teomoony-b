/* 2026-10-24 토지특성 이어받기 — VWorld 가 '토지특성 없음'(행 0)으로 답한 필지를 적어 둔다. 실패가 아니라 **확인한 사실**이다(도로 · 국공유지 등).
   적재기(--skip-loaded)가 이걸 보고 다시 묻지 않는다. 기록 표(ops 성격) — 지우지 않는다. */
IF OBJECT_ID('silver.land_char_none') IS NULL
CREATE TABLE silver.land_char_none (pnu CHAR(19) NOT NULL CONSTRAINT pk_land_char_none PRIMARY KEY, 확인시각 DATETIME2(0) NOT NULL DEFAULT SYSDATETIME());
GO
