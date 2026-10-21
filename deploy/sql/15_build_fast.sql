SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* ============================================================
   ★★ 적용하지 말 것 — 불필요하고, 문법 오류가 있다 (2026-10-15)

     전제가 틀렸다. "커서 54,064회니까 느리겠지" 로 썼는데, 실측하니
     build 가 **1초**다. 커서는 병목이 아니었다.
     진짜 느린 것은 API 호출이다(법정동 x 4종, 페이지당 100건 상한).
     SQL 을 고쳐서 줄어드는 시간이 아니다.

     게다가 테이블 변수 컬럼명 `rule` 이 T-SQL 예약어라 적용도 실패한다.
     고치지 않고 둔다 — 고쳐봐야 쓸 일이 없고, "측정 없이 최적화했다" 는
     기록으로 남기는 편이 낫다.

     혹시 전국 규모에서 build 가 실제로 느려지면 그때 꺼내 쓸 것.
     그때는 `rule` -> `grp_rule` 로 바꾸면 된다.
   ============================================================ */
/* ============================================================
   15_build_fast : 단지 발급을 커서에서 집합 연산으로

   ★ 왜
     usp_build_complexes 가 단지 하나마다 usp_resolve_complex 를 불렀다.
     단지 54,064개 x (SELECT + UPDATE 또는 INSERT x2) = 10만 회 이상의 왕복.
     build 한 번이 수 분씩 걸리는 유일한 이유다.

   ★ 바뀌지 않는 것
     - 단지를 묶는 규칙 (root_bldrgst_pk)          그대로
     - 식별 근거 (complex_identity 의 ROOT_PK)      그대로
     - 이름 우선순위 (14_complex_nm.sql)            그대로
     - **기존 단지코드**                            그대로
       identity 로 먼저 찾으므로 이미 있는 단지는 INSERT 되지 않는다.

   ★ 바뀌는 것
     새로 발급되는 단지의 complex_id 순서. 커서는 root_pk 순으로 하나씩 받았고
     집합 INSERT 는 그렇지 않다. 코드값 자체에 의미가 없고 identity 로 재현되므로
     문제가 되지 않지만, 적어둔다.

   ★ usp_resolve_complex 는 지우지 않는다
     단건 호출이 필요한 자리가 남아 있고, 이 프로시저가 틀렸을 때 비교 대상이
     있어야 한다.

   ★ 검증 (적용 전후로 돌려 비교할 것)
       SELECT COUNT(*) FROM gold.complex;
       SELECT COUNT(*) FROM gold.complex_identity WHERE identity_type='ROOT_PK';
       SELECT COUNT(*) FROM gold.complex c
         WHERE NOT EXISTS (SELECT 1 FROM gold.complex_identity i
                            WHERE i.complex_id=c.complex_id);   -- 0 이어야 한다
   ============================================================ */
USE Teomoony;
GO

CREATE OR ALTER PROCEDURE gold.usp_build_complexes
    @sigungu_cd CHAR(5) = NULL,
    @bjdong_cd  CHAR(5) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /* ---- root_bldrgst_pk 채우기 ('0'/공백/NULL = 부모 없음) ---- */
    UPDATE silver.bld_basis_outline
       SET root_bldrgst_pk =
           CASE WHEN NULLIF(LTRIM(RTRIM(ISNULL(mgm_up_bldrgst_pk,''))),'') IS NULL
                  OR LTRIM(RTRIM(mgm_up_bldrgst_pk)) = '0'
                THEN mgm_bldrgst_pk
                ELSE LTRIM(RTRIM(mgm_up_bldrgst_pk))
           END
     WHERE is_current = 1
       AND (@sigungu_cd IS NULL OR sigungu_cd = @sigungu_cd)
       AND (@bjdong_cd  IS NULL OR bjdong_cd  = @bjdong_cd);

    /* ---- 단지 발급 (집합 연산) ----
       예전에는 커서로 단지 하나씩 usp_resolve_complex 를 불렀다. 단지가 54,064개라
       SELECT + UPDATE/INSERT 가 10만 번 넘게 왕복해 build 하나가 수 분씩 걸렸다.
       하는 일은 같다. 호출 방식만 바꾼다:

         1) identity 로 찾히면 -> 이름 갱신      (예전 usp_resolve_complex 의 UPDATE 경로)
         2) 없으면            -> INSERT + identity (예전 INSERT 경로)

       usp_resolve_complex 는 그대로 둔다. 단건 호출이 필요한 자리가 남아 있고,
       무엇보다 이 프로시저가 틀렸을 때 비교 대상이 있어야 한다.

       OUTPUT ... INTO 는 FK 가 걸린 테이블을 대상으로 못 쓴다(complex_identity 가
       gold.complex 를 참조한다). 테이블 변수를 한 번 거친다. */
    DECLARE @src TABLE (
        root_pk  VARCHAR(100) PRIMARY KEY,
        nm       NVARCHAR(200),
        nm_src   VARCHAR(10),
        sgg      CHAR(5),
        bjd      CHAR(5),
        rule     VARCHAR(30)
    );

    INSERT INTO @src (root_pk, nm, nm_src, sgg, bjd, rule)
        SELECT b.root_bldrgst_pk,
               /* ★ 단지명: 총괄표제부 > 집합건축물 표제부 > 일반건축물
                  예전에는 총괄표제부('1')만 봤다. 총괄표제부는 전체의 1,947건뿐이라
                  단지의 99%가 이름을 못 받고 주소 문자열로 떨어졌다.
                  연립다세대는 한 동짜리 집합건축물('3')이라 이름이 거기 있다
                  (regstr_kind_cd=3 의 54%가 bld_nm 보유).
                  전유부('4')는 쓰지 않는다 — root_bldrgst_pk 가 표제부를 가리켜
                  다단계 단지에서 단지의 root 와 어긋난다. */
               COALESCE(
                   MAX(CASE WHEN b.regstr_kind_cd='1' THEN NULLIF(LTRIM(RTRIM(b.bld_nm)),'') END),
                   MAX(CASE WHEN b.regstr_kind_cd='3' THEN NULLIF(LTRIM(RTRIM(b.bld_nm)),'') END),
                   MAX(CASE WHEN b.regstr_kind_cd='2' THEN NULLIF(LTRIM(RTRIM(b.bld_nm)),'') END)),
               CASE WHEN MAX(CASE WHEN b.regstr_kind_cd='1' THEN NULLIF(LTRIM(RTRIM(b.bld_nm)),'') END) IS NOT NULL THEN 'RECAP'
                    WHEN MAX(CASE WHEN b.regstr_kind_cd='3' THEN NULLIF(LTRIM(RTRIM(b.bld_nm)),'') END) IS NOT NULL THEN 'TITLE'
                    WHEN MAX(CASE WHEN b.regstr_kind_cd='2' THEN NULLIF(LTRIM(RTRIM(b.bld_nm)),'') END) IS NOT NULL THEN 'GENERAL'
               END,
               MAX(b.sigungu_cd), MAX(b.bjdong_cd),
               CASE WHEN MAX(CASE WHEN b.regstr_kind_cd='1' THEN 1 ELSE 0 END) = 1
                    THEN 'RECAP' ELSE 'STANDALONE' END
        FROM silver.bld_basis_outline b
        WHERE b.is_current = 1
          AND b.regstr_kind_cd IN ('1','2','3')      -- 전유부 제외
          AND b.root_bldrgst_pk IS NOT NULL
          AND (@sigungu_cd IS NULL OR b.sigungu_cd = @sigungu_cd)
          AND (@bjdong_cd  IS NULL OR b.bjdong_cd  = @bjdong_cd)
        GROUP BY b.root_bldrgst_pk;

    /* 1) 이미 있는 단지 — 이름만 갱신 */
    UPDATE c
       SET complex_nm = CASE WHEN s.nm IS NOT NULL         THEN s.nm
                             WHEN c.complex_nm_src = 'ADDR' THEN NULL
                             ELSE c.complex_nm END,
           complex_nm_src = CASE WHEN s.nm IS NOT NULL         THEN s.nm_src
                                 WHEN c.complex_nm_src = 'ADDR' THEN NULL
                                 ELSE c.complex_nm_src END,
           updated_at = SYSDATETIME()
      FROM gold.complex c
      JOIN gold.complex_identity i
        ON i.complex_id = c.complex_id AND i.identity_type = 'ROOT_PK'
      JOIN @src s ON s.root_pk = i.identity_val;

    /* 2) 새 단지 — 발급하고 식별 근거를 남긴다 */
    DECLARE @new TABLE (complex_id INT, root_pk VARCHAR(100));

    INSERT INTO gold.complex (root_bldrgst_pk, complex_nm, complex_nm_src,
                              sigungu_cd, bjdong_cd, grouping_rule)
    OUTPUT inserted.complex_id, inserted.root_bldrgst_pk INTO @new (complex_id, root_pk)
    SELECT s.root_pk, s.nm, s.nm_src, s.sgg, s.bjd, s.rule
      FROM @src s
     WHERE NOT EXISTS (SELECT 1 FROM gold.complex_identity i
                        WHERE i.identity_type = 'ROOT_PK' AND i.identity_val = s.root_pk);

    INSERT INTO gold.complex_identity (complex_id, identity_type, identity_val, is_primary)
    SELECT complex_id, 'ROOT_PK', root_pk, 1 FROM @new;

    /* ---- 단지 <-> 대장 매핑 ---- */
    MERGE gold.complex_bld AS tgt
    USING (
        SELECT ci.complex_id, b.mgm_bldrgst_pk, b.regstr_kind_cd,
               CASE WHEN b.regstr_kind_cd = '1' THEN 1 ELSE 0 END AS is_recap,
               CASE WHEN b.mgm_bldrgst_pk = b.root_bldrgst_pk
                    THEN 'ROOT' ELSE 'CHILD' END AS link_rule
        FROM silver.bld_basis_outline b
        JOIN gold.complex_identity ci
          ON ci.identity_type = 'ROOT_PK' AND ci.identity_val = b.root_bldrgst_pk
        WHERE b.is_current = 1 AND b.regstr_kind_cd IN ('1','2','3')
          AND (@sigungu_cd IS NULL OR b.sigungu_cd = @sigungu_cd)
          AND (@bjdong_cd  IS NULL OR b.bjdong_cd  = @bjdong_cd)
    ) AS src
       ON tgt.mgm_bldrgst_pk = src.mgm_bldrgst_pk
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (complex_id, mgm_bldrgst_pk, regstr_kind_cd, is_recap, link_rule)
        VALUES (src.complex_id, src.mgm_bldrgst_pk, src.regstr_kind_cd, src.is_recap, src.link_rule);

    /* ---- 단지 <-> 필지 (기본개요 대지 + 부속지번 합집합) ---- */
    MERGE gold.complex_pnu AS tgt
    USING (
        /* (complex_id, pnu) 로 묶는다. 한 PNU 가 대지이면서 동시에
           다른 동의 부속지번일 수 있어, 묶지 않으면 PK 가 터진다.
           MAX('MAIN','ATTACHED') = 'MAIN' -> 대지 역할 우선. */
        SELECT cb.complex_id, x.pnu, MAX(x.pnu_role) AS pnu_role
        FROM gold.complex_bld cb
        CROSS APPLY (
            SELECT b.pnu, 'MAIN' AS pnu_role
            FROM silver.bld_basis_outline b
            WHERE b.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND b.is_current = 1 AND b.pnu IS NOT NULL
            UNION ALL
            SELECT a.atch_pnu, 'ATTACHED'
            FROM silver.bld_atch_jibun a
            WHERE a.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND a.is_current = 1 AND a.atch_pnu IS NOT NULL
        ) x
        GROUP BY cb.complex_id, x.pnu
    ) AS src
       ON tgt.complex_id = src.complex_id AND tgt.pnu = src.pnu
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (complex_id, pnu, pnu_role) VALUES (src.complex_id, src.pnu, src.pnu_role);

    /* ---- 요약값 재계산 ---- */
    WITH agg AS (
        SELECT cb.complex_id,
               SUM(CASE WHEN cb.regstr_kind_cd IN ('2','3') THEN 1 ELSE 0 END) AS dong_cnt,
               MAX(CASE WHEN cb.is_recap = 1 THEN 1 ELSE 0 END)                AS has_recap
        FROM gold.complex_bld cb GROUP BY cb.complex_id
    ), tagg AS (
        SELECT cb.complex_id,
               SUM(t.hhld_cnt) AS hhld_sum, SUM(t.tot_area) AS area_sum,
               MIN(NULLIF(t.use_apr_day,'')) AS min_apr, MAX(NULLIF(t.use_apr_day,'')) AS max_apr
        FROM gold.complex_bld cb
        JOIN silver.bld_title t ON t.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND t.is_current = 1
        GROUP BY cb.complex_id
    ), pnuagg AS (
        SELECT complex_id, COUNT(*) AS pnu_cnt FROM gold.complex_pnu GROUP BY complex_id
    ), rep AS (
        /* 대표 = 총괄표제부 우선, 없으면 연면적 최대 */
        SELECT cb.complex_id, b.pnu, b.plat_plc, b.new_plat_plc,
               ROW_NUMBER() OVER (PARTITION BY cb.complex_id
                   ORDER BY cb.is_recap DESC, ISNULL(t.tot_area,0) DESC, b.mgm_bldrgst_pk) AS rn
        FROM gold.complex_bld cb
        JOIN silver.bld_basis_outline b ON b.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND b.is_current = 1
        LEFT JOIN silver.bld_title t    ON t.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND t.is_current = 1
    )
    UPDATE c
       SET c.dong_cnt       = a.dong_cnt,
           c.has_recap      = a.has_recap,
           c.pnu_cnt        = p.pnu_cnt,
           c.hhld_cnt_sum   = tg.hhld_sum,
           c.tot_area_sum   = tg.area_sum,
           c.oldest_use_apr = tg.min_apr,
           c.latest_use_apr = tg.max_apr,
           c.rep_pnu        = r.pnu,
           c.rep_plat_plc   = r.plat_plc,
           c.rep_road_addr  = r.new_plat_plc,
           c.updated_at     = SYSDATETIME()
      FROM gold.complex c
      JOIN agg a         ON a.complex_id  = c.complex_id
      LEFT JOIN tagg tg  ON tg.complex_id = c.complex_id
      LEFT JOIN pnuagg p ON p.complex_id  = c.complex_id
      LEFT JOIN rep r    ON r.complex_id  = c.complex_id AND r.rn = 1;

    UPDATE cp SET is_representative = 1
      FROM gold.complex_pnu cp
      JOIN gold.complex c ON c.complex_id = cp.complex_id AND c.rep_pnu = cp.pnu;

    /* 단지명이 비면 대표 주소로 대체. 출처를 'ADDR' 로 남겨, 나중에 진짜 이름이
       생기면 usp_resolve_complex 가 덮을 수 있게 한다. */
    UPDATE gold.complex
       SET complex_nm = rep_plat_plc, complex_nm_src = 'ADDR'
     WHERE complex_nm IS NULL AND rep_plat_plc IS NOT NULL;
END
GO
