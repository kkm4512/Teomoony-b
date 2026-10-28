/* 381 (2026-10-28 · 10-29 아침: ALTER 와 ADD CONSTRAINT 가 한 배치라 컴파일 때 8111 — GO 로 나눔) 폐쇄대장 허브판(__hub)에 기본키 — hub_swap.build 가 NOT NULL 칸을 NULL 로 풀어 PK 를 못 만들었다(8111). 열쇠 칸만 되돌린다. */
SELECT 빈열쇠_표제부 = (SELECT COUNT(*) FROM silver.bld_closed_title__hub WHERE mgm_shtreg_pk IS NULL),
       빈열쇠_총괄 = (SELECT COUNT(*) FROM silver.bld_closed_recap__hub WHERE mgm_shtreg_pk IS NULL);
ALTER TABLE silver.bld_closed_title__hub ALTER COLUMN mgm_shtreg_pk VARCHAR(30) NOT NULL;
GO
ALTER TABLE silver.bld_closed_title__hub ADD CONSTRAINT pk_bld_closed_title_h PRIMARY KEY CLUSTERED (mgm_shtreg_pk) WITH (DATA_COMPRESSION = PAGE, MAXDOP = 4);
ALTER TABLE silver.bld_closed_recap__hub ALTER COLUMN mgm_shtreg_pk VARCHAR(30) NOT NULL;
GO
ALTER TABLE silver.bld_closed_recap__hub ADD CONSTRAINT pk_bld_closed_recap_h PRIMARY KEY CLUSTERED (mgm_shtreg_pk) WITH (DATA_COMPRESSION = PAGE, MAXDOP = 4);
SELECT 끝 = 1;
