SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* ============================================================
   13_scope : 적재 범위를 뷰가 알게 한다

   ★ 왜 필요한가 (CONTEXT.md 4-21, 4-22)
     "대장이 없다" 와 "그 법정동을 아직 적재하지 않았다" 가 지금까지
     똑같이 `대장 0` 으로 보였다. 숫자만 보면 구분이 안 된다.

       v_newbuild_gap 상위 20행 중 19개가 사용승인 1998~2005 구축이었는데
       `대장 0` 이라 신축처럼 보였다. 전부 범위 밖이었을 뿐이다.

     사람도 같은 실수를 한다. 4-22 ④ 에 이 세션에서 그 함정에 빠진 기록이 있다.
     판단 근거를 뷰 안에 넣어 두는 것이 유일한 해법이다.

   근거는 meta.ingest_run 이다. getBrBasisOulnInfo 를 성공으로 끝낸
   법정동만 "적재 범위 안" 이다. 대장 행이 있는지로 유도하지 않는 이유:
   그러면 **"적재했는데 진짜 0건"** 과 **"적재 안 함"** 이 다시 합쳐진다.
   구분하려고 만드는 뷰가 구분을 잃으면 의미가 없다.
   ============================================================ */
USE Teomoony;
GO

/* ------------------------------------------------------------
   meta.v_lawd_scope — 건축물대장을 적재한 법정동

   scope_key 는 '11290/13800' 형식(시군구5/법정동뒤5)이다.
   --bjdong 없이 돌린 경우 '11290/' 뒤에 별표가 붙은 값이 들어올 수 있어 LIKE 로 거른다.
   ★ 2026-10-21: 여기 원래 그 값을 따옴표째 적어 뒀는데, 그 안의 슬래시+별표가
     **주석을 하나 더 열었다.** SQL Server 는 블록 주석이 **중첩**된다 —
     아래 닫기는 그 안쪽 것만 닫고, 바깥 주석은 열린 채로 CREATE VIEW 를
     통째로 삼킨다. 그래서 이 파일은 **뷰를 안 만들고 조용히 지나갔다.**
     (CONTEXT 에 적어 둔 '주석 안의 닫기' 와 **거울상**인 실수다.)
   ------------------------------------------------------------ */
IF OBJECT_ID('meta.v_lawd_scope') IS NOT NULL DROP VIEW meta.v_lawd_scope;
GO
CREATE VIEW meta.v_lawd_scope
AS
SELECT x.lawd_cd,
       적재시각 = MAX(x.finished_at),
       적재행수 = SUM(x.row_count),
       실행횟수 = COUNT(*)
FROM (
    SELECT r.finished_at, r.row_count,
           lawd_cd = LEFT(r.scope_key, 5) + SUBSTRING(r.scope_key, 7, 5)
    FROM meta.ingest_run r
    JOIN meta.api_source s ON s.source_id = r.source_id
    WHERE s.operation = 'getBrBasisOulnInfo'
      AND r.status = 'OK'
      AND r.scope_key LIKE '[0-9][0-9][0-9][0-9][0-9]/[0-9][0-9][0-9][0-9][0-9]'
) x
GROUP BY x.lawd_cd;
GO

/* ------------------------------------------------------------
   gold.v_rtms_gap — 거래 한 건이 왜 단지에 안 붙었는지

   OK            붙었다
   MASKED        지번이 '1**' 로 가려져 영구 불가 (5장, 설계 한계)
   NO_PNU        PNU 조립 자체가 실패. 현재 0건이지만 버그가 숨는 자리다
   OUT_OF_SCOPE  그 법정동 대장을 적재하지 않음      <- 기능 부족이 아니라 범위
   NO_BLD        적재했는데 그 지번에 대장이 없음     <- 진짜 신축 시차 (4-13)

   CASE 순서가 의미를 정한다. 마스킹을 먼저 보는 이유: 마스킹된 행은
   PNU 가 NULL 이라 NO_PNU 로 샌다. 영구 불가가 "버그일 수 있음" 으로
   분류되면 둘 다 못 믿게 된다.
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
           ELSE                                                  'NO_BLD'
       END
FROM silver.rtms_trade t
LEFT JOIN meta.v_lawd_scope sc ON sc.lawd_cd = LEFT(t.match_pnu, 10);
GO

/* 상태별 집계. "매칭률 28.6%" 가 품질인지 범위인지 한 줄로 갈린다. */
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
   gold.v_newbuild_gap 재정의 — 12_kapt.sql 의 뷰에 '상태' 를 더한다

   본체는 그대로 두고 범위 판정만 붙였다. 기존 컬럼·순서는 유지하므로
   이 뷰를 읽던 쿼리는 그대로 동작한다.

   남은 결정: K-apt 의 PNU 를 믿을 수 없다 (4-22 ②). 보문파크뷰자이는
   kaptAddr 지번이 198-45 인데 대장·실거래는 458 이고, 그 법정동 대장을
   전수 적재한 뒤에도 198-45 에는 대장이 0건이다. 법정동 + 단지명 보조
   매칭을 들일지는 **아직 정하지 않았다.** 문자열 매칭을 다시 들이는
   일이라 원칙과 충돌한다. 여기서는 PNU 조인을 그대로 둔다.
   ------------------------------------------------------------ */
IF OBJECT_ID('gold.v_newbuild_gap') IS NOT NULL DROP VIEW gold.v_newbuild_gap;
GO
CREATE VIEW gold.v_newbuild_gap
AS
SELECT t.pnu, t.lawd_cd,
       상태 = CASE WHEN sc.lawd_cd IS NULL THEN 'OUT_OF_SCOPE' ELSE 'NO_BLD' END,
       거래 = t.cnt,
       대장 = ISNULL(b.cnt, 0),
       인허가 = ISNULL(p.cnt, 0),
       kapt = ISNULL(k.cnt, 0),
       단지명 = k.kapt_name,
       세대 = k.ho_cnt,
       동수 = k.dong_cnt,
       사용승인 = k.kapt_usedate,
       시행 = k.acompany,
       대장적재시각 = sc.적재시각
FROM (
    SELECT match_pnu AS pnu, LEFT(match_pnu,10) AS lawd_cd, COUNT(*) AS cnt
    FROM silver.rtms_trade
    WHERE match_pnu IS NOT NULL AND match_complex_id IS NULL
    GROUP BY match_pnu
) t
LEFT JOIN meta.v_lawd_scope sc ON sc.lawd_cd = t.lawd_cd
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
