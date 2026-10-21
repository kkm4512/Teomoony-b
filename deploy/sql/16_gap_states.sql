SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* ============================================================
   16_gap_states : NO_BLD 가 두 가지를 뭉개고 있었다

   13_scope.sql 의 상태 판정이 이랬다:

       CASE WHEN sc.lawd_cd IS NULL THEN 'OUT_OF_SCOPE' ELSE 'NO_BLD' END

   **대장 건수를 보지 않는다.** 범위 안이면 무조건 NO_BLD 로 떨어져서,
   "그 지번에 대장이 아예 없다" 와 "대장은 있는데 단지에 안 붙었다" 가
   같은 이름을 받았다.

   실측에서 드러났다 (2026-10-15 밤):

       1129013900103320577   거래 11 · 대장 32 · 전유부 32 · 표제부 0

   전유부만 있는 지번이다. 단지 구성이 regstr_kind_cd IN ('1','2','3') 으로
   전유부를 제외하므로 단지가 만들어지지 않는다. **설계상 정상인데**
   "대장이 없다" 로 보고되고 있었다.

   4-21 이 지적한 "뷰가 구분을 잃는다" 와 같은 종류다. 범위라는 구분을 넣느라
   그 안의 또 다른 구분을 못 봤다.

   현재 영향은 1 PNU / 11건으로 작다. 그래도 고치는 이유는 **이름이 틀린 것은
   규모가 커지면서 자라기 때문**이다. 전국이면 이 유형이 몇 건일지 모른다.

   ★ 상태 7종
       OK            붙었다
       MASKED        지번이 가려져 영구 불가 (설계 한계)
       NO_PNU        PNU 조립 자체가 실패      (버그가 숨는 자리)
       OUT_OF_SCOPE  그 법정동 대장을 적재하지 않음
       NO_BLD        적재했는데 그 지번에 대장이 0건  (신축 시차 · 나대지 · 멸실)
       NO_TITLE      대장은 있는데 전유부뿐          (설계상 정상. 조사 불필요)
       NO_LINK       표제부가 있는데도 단지에 안 붙음  ★ 이게 진짜 이상한 것
   ============================================================ */
USE Teomoony;
GO

/* PNU 단위 대장 요약. 두 뷰가 같이 쓴다. */
IF OBJECT_ID('gold.v_pnu_bld') IS NOT NULL DROP VIEW gold.v_pnu_bld;
GO
CREATE VIEW gold.v_pnu_bld
AS
SELECT pnu,
       대장 = COUNT(*),
       표제부 = SUM(CASE WHEN regstr_kind_cd IN ('1','2','3') THEN 1 ELSE 0 END),
       전유부 = SUM(CASE WHEN regstr_kind_cd = '4' THEN 1 ELSE 0 END)
FROM silver.bld_basis_outline
WHERE is_current = 1 AND pnu IS NOT NULL
GROUP BY pnu;
GO

/* ------------------------------------------------------------
   gold.v_rtms_gap — 거래 한 건이 왜 단지에 안 붙었는지

   CASE 순서가 의미를 정한다. 마스킹을 NO_PNU 보다 먼저 본다 — 마스킹된 행은
   match_pnu 가 NULL 이라 그냥 두면 전부 NO_PNU 로 샌다. 영구 불가(설계 한계)가
   "버그일 수 있음" 으로 분류되면 두 상태를 다 못 믿게 된다.
   ------------------------------------------------------------ */
IF OBJECT_ID('gold.v_rtms_gap') IS NOT NULL DROP VIEW gold.v_rtms_gap;
GO
CREATE VIEW gold.v_rtms_gap
AS
SELECT t.trade_sk,
       t.trade_kind,
       t.match_method,
       t.match_pnu,
       t.match_complex_id,
       t.umd_nm,
       t.jibun,
       t.bld_nm,
       t.deal_ymd,
       lawd_cd = LEFT(t.match_pnu, 10),
       상태 = CASE
           WHEN t.match_complex_id IS NOT NULL              THEN 'OK'
           WHEN t.jibun_masked = 1
             OR t.match_method = 'MASKED'                   THEN 'MASKED'
           WHEN t.match_pnu IS NULL                         THEN 'NO_PNU'
           WHEN sc.lawd_cd IS NULL                          THEN 'OUT_OF_SCOPE'
           WHEN ISNULL(b.대장, 0) = 0                        THEN 'NO_BLD'
           WHEN ISNULL(b.표제부, 0) = 0                      THEN 'NO_TITLE'
           ELSE                                                  'NO_LINK'
       END
FROM silver.rtms_trade t
LEFT JOIN meta.v_lawd_scope sc ON sc.lawd_cd = LEFT(t.match_pnu, 10)
LEFT JOIN gold.v_pnu_bld   b  ON b.pnu       = t.match_pnu;
GO

IF OBJECT_ID('gold.v_rtms_gap_summary') IS NOT NULL DROP VIEW gold.v_rtms_gap_summary;
GO
CREATE VIEW gold.v_rtms_gap_summary
AS
SELECT 상태,
       건수 = COUNT(*),
       법정동수 = COUNT(DISTINCT lawd_cd),
       비율 = CAST(100.0 * COUNT(*) / NULLIF(SUM(COUNT(*)) OVER (), 0) AS DECIMAL(5,1))
FROM gold.v_rtms_gap
GROUP BY 상태;
GO

/* ------------------------------------------------------------
   gold.v_newbuild_gap — "실거래는 붙었는데 단지가 없는" PNU 를 축별로 비교

   기존 컬럼·순서는 유지한다. 상태 판정만 대장 요약을 보도록 고쳤다.
   ------------------------------------------------------------ */
IF OBJECT_ID('gold.v_newbuild_gap') IS NOT NULL DROP VIEW gold.v_newbuild_gap;
GO
CREATE VIEW gold.v_newbuild_gap
AS
SELECT t.pnu, t.lawd_cd,
       상태 = CASE
           WHEN sc.lawd_cd IS NULL        THEN 'OUT_OF_SCOPE'
           WHEN ISNULL(pb.대장, 0)   = 0   THEN 'NO_BLD'
           WHEN ISNULL(pb.표제부, 0) = 0   THEN 'NO_TITLE'
           ELSE                                'NO_LINK'
       END,
       거래 = t.cnt,
       대장 = ISNULL(b.cnt, 0),
       인허가 = ISNULL(p.cnt, 0),
       kapt = ISNULL(k.cnt, 0),
       단지명 = k.kapt_name,
       세대 = k.ho_cnt,
       동수 = k.dong_cnt,
       사용승인 = k.kapt_usedate,
       시행 = k.acompany,
       대장적재시각 = sc.적재시각,
       표제부 = ISNULL(pb.표제부, 0),
       전유부 = ISNULL(pb.전유부, 0)
FROM (
    SELECT match_pnu AS pnu, LEFT(match_pnu,10) AS lawd_cd, COUNT(*) AS cnt
    FROM silver.rtms_trade
    WHERE match_pnu IS NOT NULL AND match_complex_id IS NULL
    GROUP BY match_pnu
) t
LEFT JOIN meta.v_lawd_scope sc ON sc.lawd_cd = t.lawd_cd
LEFT JOIN gold.v_pnu_bld    pb ON pb.pnu     = t.pnu
OUTER APPLY (SELECT COUNT(*) AS cnt FROM silver.bld_basis_outline b
              WHERE b.is_current = 1 AND b.pnu = t.pnu) b
OUTER APPLY (SELECT COUNT(*) AS cnt FROM silver.arch_permit a
              WHERE a.is_current = 1 AND a.pnu = t.pnu) p
/* 여러 단지가 한 PNU 를 쓸 수 있다(장위자이레디언트 1~4단지). 건수와 대표 1건을
   따로 뽑는다. 컬럼별 MAX 로 섞으면 4-16 의 실수를 반복한다. */
OUTER APPLY (SELECT COUNT(*) AS cnt FROM silver.kapt_complex k
              WHERE k.is_current = 1 AND k.pnu = t.pnu) k2
OUTER APPLY (
    SELECT TOP 1 kapt_name, ho_cnt, dong_cnt, kapt_usedate, acompany, cnt = k2.cnt
    FROM silver.kapt_complex k
    WHERE k.is_current = 1 AND k.pnu = t.pnu
    ORDER BY k.ho_cnt DESC, k.kapt_code
) k;
GO
