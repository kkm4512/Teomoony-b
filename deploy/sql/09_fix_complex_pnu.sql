SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* ============================================================
   09_fix_complex_pnu

   버그: usp_build_complexes 의 단지<->필지 MERGE 가
         PK 위반으로 터진다.

     Violation of PRIMARY KEY 'pk_complex_pnu'
     duplicate key (5673, 1111018400101230013)

   원인: 한 PNU 가 어떤 동의 "대지"(MAIN)이면서 동시에
         다른 동의 "부속지번"(ATTACHED)일 수 있다.
         SELECT DISTINCT complex_id, pnu, pnu_role 은 역할이 다르면
         서로 다른 행으로 보므로 두 행이 남고, PK(complex_id, pnu)에
         같은 키를 두 번 INSERT 하려다 실패한다.

   수정: (complex_id, pnu) 로 묶고 역할은 MAX 로 고른다.
         MAX('MAIN','ATTACHED') = 'MAIN' (M > A) 이므로
         대지 역할이 부속지번보다 우선한다.

   ※ 청운동 1개 법정동에서는 이런 필지가 없어 드러나지 않았다.
     종로구 전체로 넓히자 바로 터졌다.
   ============================================================ */
USE Teomoony;
GO

IF OBJECT_ID('gold.usp_build_complexes') IS NOT NULL DROP PROCEDURE gold.usp_build_complexes;
GO
CREATE PROCEDURE gold.usp_build_complexes
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

    /* ---- 단지 발급 ---- */
    DECLARE @id INT, @iv VARCHAR(100), @nm NVARCHAR(200),
            @sgg CHAR(5), @bjd CHAR(5), @rule VARCHAR(30);

    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT b.root_bldrgst_pk,
               MAX(CASE WHEN b.regstr_kind_cd = '1' THEN b.bld_nm END),
               MAX(b.sigungu_cd), MAX(b.bjdong_cd),
               CASE WHEN MAX(CASE WHEN b.regstr_kind_cd='1' THEN 1 ELSE 0 END) = 1
                    THEN 'RECAP' ELSE 'STANDALONE' END
        FROM silver.bld_basis_outline b
        WHERE b.is_current = 1
          AND b.regstr_kind_cd IN ('1','2','3')
          AND b.root_bldrgst_pk IS NOT NULL
          AND (@sigungu_cd IS NULL OR b.sigungu_cd = @sigungu_cd)
          AND (@bjdong_cd  IS NULL OR b.bjdong_cd  = @bjdong_cd)
        GROUP BY b.root_bldrgst_pk;

    OPEN cur;
    FETCH NEXT FROM cur INTO @iv, @nm, @sgg, @bjd, @rule;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC gold.usp_resolve_complex 'ROOT_PK', @iv, @nm, @sgg, @bjd, @rule, @iv,
             @complex_id = @id OUTPUT;
        FETCH NEXT FROM cur INTO @iv, @nm, @sgg, @bjd, @rule;
    END
    CLOSE cur; DEALLOCATE cur;

    /* ---- 단지 <-> 대장 ---- */
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

    /* ---- 단지 <-> 필지 ----
       ★ 수정 지점. (complex_id, pnu) 로 묶어 역할을 하나로 접는다.
         한 PNU 가 대지이자 다른 동의 부속지번일 수 있어서,
         묶지 않으면 같은 키가 두 번 들어가 PK 가 터진다.
         MAX('MAIN','ATTACHED') = 'MAIN' -> 대지 역할 우선. */
    MERGE gold.complex_pnu AS tgt
    USING (
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

    /* ---- 요약값 ---- */
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

    UPDATE gold.complex
       SET complex_nm = rep_plat_plc
     WHERE complex_nm IS NULL AND rep_plat_plc IS NOT NULL;
END
GO

PRINT '09_fix_complex_pnu done.';
GO
