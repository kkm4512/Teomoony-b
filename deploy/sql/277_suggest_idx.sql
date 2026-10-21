/* 277. 자동완성용 색인 (2026-10-21, 사장님 요청 16:02)
   ★ 상가 61만 건은 '포함' 으로 찾으면 글자 칠 때마다 표를 훑는다. 자동완성은
     **앞부분 일치**(스타벅스 → '스타벅스 장위점')로 찾고, 그 범위탐색을 이 색인이 받친다.
     화면에 그릴 칸을 INCLUDE 해서 본문으로 안 돌아가게 한다.
   ★ 학원(2.7만)·학교(1.2만)·재개발(5.5천)·역(1천)·유치원(8백)은 작아서 '포함' 으로도 빠르다 - 색인 안 만든다.
   ★ 다시 돌려도 된다. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_semas_nm' AND object_id = OBJECT_ID('silver.semas_store'))
    CREATE INDEX ix_semas_nm ON silver.semas_store (bizes_nm)
        INCLUDE (brch_nm, lon, lat, adong_nm, inds_scls_nm, rdnm_adr)
        WHERE is_current = 1
        WITH (MAXDOP = 4);
GO
PRINT '277 완료';
/* 277-2 단지 이름 — 자동완성 측정에서 단지만 790ms(나머지 전부 20ms 이하). 53만 행 본문을 '포함' 으로 훑었다.
   이름이 **진짜 이름**인 단지(complex_nm_src <> 'ADDR')만 담은 좁은 거른 색인으로 훑을 양을 줄인다.
   ★ 자동완성 쿼리의 WHERE 에 complex_nm_src <> 'ADDR' 가 **그대로** 있어야 이 색인을 탄다. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_complex_nm_real' AND object_id = OBJECT_ID('gold.complex'))
    CREATE INDEX ix_complex_nm_real ON gold.complex (complex_nm)
        INCLUDE (complex_nm_src, hhld_cnt_sum, dong_cnt, rep_plat_plc, centroid_lat, centroid_lng)
        WHERE complex_nm_src <> 'ADDR'
        WITH (MAXDOP = 4);
GO
SELECT 진짜이름단지 = COUNT(*) FROM gold.complex WITH (NOLOCK) WHERE complex_nm_src <> 'ADDR';
GO
PRINT '277-2 완료';
