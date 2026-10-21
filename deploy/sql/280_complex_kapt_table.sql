/* 280. K-apt 연결을 표로 굳힌다 — gold.complex_kapt + gold.usp_refresh_complex_kapt (2026-10-21, 사장님 승인 17:09)
   ★ 왜: 신축 18곳 중 12곳이 K-apt 로 기존 단지와 이어져 있다(래미안퍼스트하이 ↔ 49101 등) — 지도에 같은 아파트가 두 번.
     빼려면 신축 뷰가 K-apt 연결을 봐야 하는데 gold.v_complex_kapt 가 2.2초라 지도 마커(지도를 움직일 때마다)에 못 쓴다.
     상세의 _q_kapt 도 이 뷰라 상세에서 제일 느린 갈래였다(1.2초).
   ★ 규칙은 **뷰 한 곳에만** 있다(279 까지의 v_complex_kapt). 표는 그 뷰를 SELECT * 로 굳힌 것뿐이다 —
     규칙을 두 군데 두지 않는다. 뷰 칸이 바뀌면 갱신 프로시저가 **시끄럽게** 깨진다(조용히 틀리지 않는다).
   ★ 상세와 신축이 **둘 다 이 표**를 본다 — 한쪽은 뷰, 한쪽은 표면 갱신 사이에 갈라진다(작업방식 10장).
   ★ 갱신: K-apt 적재(load_kapt.py) 끝 · 단지 구성(teomoony_ingest build) 끝에서 부른다. 손으로도 EXEC 하면 된다.
     지우고 다시 넣는 것을 **트랜잭션 하나**로 — 읽는 쪽이 빈 표를 보지 않는다(2~3초 기다릴 뿐).
   ★ 파생 표라 지우고 다시 만들어도 된다(작업방식 7장의 예외). */
SET NOCOUNT ON;
GO
IF OBJECT_ID('gold.complex_kapt') IS NULL
BEGIN
    SELECT * INTO gold.complex_kapt FROM gold.v_complex_kapt WHERE 1 = 0;
    ALTER TABLE gold.complex_kapt ADD 굳힌시각 DATETIME2(0) NOT NULL CONSTRAINT df_complex_kapt_t DEFAULT SYSDATETIME();
    ALTER TABLE gold.complex_kapt ALTER COLUMN complex_id INT NOT NULL;
    ALTER TABLE gold.complex_kapt ADD CONSTRAINT pk_complex_kapt PRIMARY KEY CLUSTERED (complex_id);
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'uq_complex_kapt_code' AND object_id = OBJECT_ID('gold.complex_kapt'))
    CREATE UNIQUE INDEX uq_complex_kapt_code ON gold.complex_kapt (kapt_code);
GO
CREATE OR ALTER PROCEDURE gold.usp_refresh_complex_kapt
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @t DATETIME2 = SYSDATETIME();
    SELECT * INTO #v FROM gold.v_complex_kapt;          /* 무거운 계산은 트랜잭션 밖에서 */
    BEGIN TRAN;
        DELETE FROM gold.complex_kapt;
        INSERT INTO gold.complex_kapt SELECT v.*, SYSDATETIME() FROM #v v;
    COMMIT;
    SELECT 연결 = (SELECT COUNT(*) FROM gold.complex_kapt), 초 = DATEDIFF(SECOND, @t, SYSDATETIME());
END
GO
EXEC gold.usp_refresh_complex_kapt;
GO
/* 신축 뷰 — 278 정의 + K-apt 로 기존 단지와 이어진 것도 뺀다 */
CREATE OR ALTER VIEW gold.v_newbuild
AS
SELECT k.kapt_code,
       k.kapt_name,
       k.pnu,
       k.bjd_code,
       lawd_nm      = l.emd_nm,
       k.kapt_addr,
       k.doro_juso,
       세대          = k.ho_cnt,
       동수          = k.dong_cnt,
       사용승인       = k.kapt_usedate,
       k.top_floor,
       난방          = k.code_heat_nm,
       시공          = k.bcompany,
       시행          = k.acompany,
       거래          = ISNULL(t.cnt, 0),
       최근거래       = t.last_ymd,
       최고가         = t.max_amount,
       centroid_lat = p.centroid_lat,
       centroid_lng = p.centroid_lng,
       인허가         = ISNULL(a.cnt, 0)
FROM silver.kapt_complex k
/* 그 법정동 대장을 적재했는가. 안 했으면 "대장이 없다" 고 말할 수 없다. */
JOIN meta.v_lawd_scope sc ON sc.lawd_cd = k.bjd_code
LEFT JOIN meta.lawd_code l ON l.lawd_cd = k.bjd_code
LEFT JOIN gold.v_pnu_bld b ON b.pnu     = k.pnu
OUTER APPLY (
    SELECT TOP 1 centroid_lat, centroid_lng
    FROM silver.cadastral_parcel cp
    WHERE cp.is_current = 1 AND cp.pnu = k.pnu AND cp.centroid_lat IS NOT NULL
    ORDER BY cp.pnu
) p
OUTER APPLY (
    /* 2026-10-21 QA: 해제는 건수·범위에서 빼고 따로 센다(CONTEXT 4-5 · 11-117). */
    SELECT cnt = SUM(CASE WHEN r.is_canceled = 0 THEN 1 ELSE 0 END),
           해제 = SUM(CAST(r.is_canceled AS INT)),
           last_ymd = MAX(CASE WHEN r.is_canceled = 0 THEN r.deal_ymd END),
           max_amount = MAX(CASE WHEN r.is_canceled = 0 AND r.is_rent = 0
                                 THEN r.deal_amount END)
    FROM silver.rtms_trade r
    WHERE r.match_pnu = k.pnu AND r.match_complex_id IS NULL
) t
OUTER APPLY (
    SELECT cnt = COUNT(*) FROM silver.arch_permit ap
    WHERE ap.is_current = 1 AND ap.pnu = k.pnu
) a
WHERE k.is_current = 1
  AND k.pnu IS NOT NULL
  AND ISNULL(b.표제부, 0) = 0      -- 대장(표제부)이 아직 없다
  /* 278: 부속지번으로라도 어느 단지에 들어 있으면 대장이 있는 것이다 */
  AND NOT EXISTS (SELECT 1 FROM gold.complex_pnu cp WHERE cp.pnu = k.pnu)
  /* 280: K-apt 로 기존 단지와 이어졌으면(관리비가 그 단지에 붙는다) 그 단지다 */
  AND NOT EXISTS (SELECT 1 FROM gold.complex_kapt ck WHERE ck.kapt_code = k.kapt_code);
GO
SELECT 신축 = COUNT(*), 목록 = STRING_AGG(kapt_name, ' | ') FROM gold.v_newbuild;
