/* 327_complex_nm_ns : 단지 이름 띄어쓰기 뺀 계산 칸 + 거른 색인 (2026-10-23 사장님 "123 하고" — 자동완성 속도)
   ★ 11-225 에서 이름을 띄어쓰기 빼고 맞추게 했더니(REPLACE 를 53만 행에) 자동완성이 0.3 → 0.6~0.9초.
     계산 칸(저장 안 함) + 277 과 같은 거른 색인(complex_nm_src <> 'ADDR')이면 색인만 훑는다. 쿼리는 complex_nm_ns 를 그대로 쓴다.
   ★ 277 거른 색인과 SET 조건이 같다 — 적재(pymssql)가 지금 gold.complex 를 고칠 수 있으면 이것도 된다. */
SET QUOTED_IDENTIFIER ON; SET ANSI_NULLS ON; SET ANSI_PADDING ON; SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;
GO
IF COL_LENGTH('gold.complex', 'complex_nm_ns') IS NULL
    ALTER TABLE gold.complex ADD complex_nm_ns AS CAST(REPLACE(complex_nm, N' ', N'') AS NVARCHAR(200));
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_complex_nm_ns' AND object_id = OBJECT_ID('gold.complex'))
    CREATE INDEX ix_complex_nm_ns ON gold.complex (complex_nm_ns)
        INCLUDE (complex_nm, complex_nm_src, hhld_cnt_sum, dong_cnt, rep_plat_plc, centroid_lat, centroid_lng, merged_into)
        WHERE complex_nm_src <> 'ADDR'
        WITH (MAXDOP = 4);
GO
SELECT 칸 = COL_LENGTH('gold.complex', 'complex_nm_ns'), 색인 = (SELECT COUNT(*) FROM sys.indexes WHERE name = 'ix_complex_nm_ns');
