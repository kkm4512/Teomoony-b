/* 354 usp_build_complexes — root UPDATE 뺌 (허브 대장으로 바꿔 끼운 뒤) */
CREATE OR ALTER PROCEDURE gold.usp_build_complexes
    @sigungu_cd CHAR(5) = NULL,
    @bjdong_cd  CHAR(5) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /* ---- root_bldrgst_pk: 2026-10-25 허브 대장으로 바꿔 끼운 뒤로는 표를 만들 때 이미 채워져 있다(hub_views.py · 같은 식).
       예전처럼 여기서 UPDATE 하면 허브에서 만든 표를 고치게 되고, 전국이면 수천만 줄을 다시 쓴다 → 뺐다. ---- */

    /* ---- 단지 발급 ---- */
    DECLARE @id INT, @iv VARCHAR(100), @nm NVARCHAR(200), @nmsrc VARCHAR(10),
            @sgg CHAR(5), @bjd CHAR(5), @rule VARCHAR(30);

    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT b.root_bldrgst_pk,
               /* ★ 단지명: 총괄표제부 > 집합건축물 표제부 > 일반건축물
                  예전에는 총괄표제부('1')만 봤다. 총괄표제부는 전체의 1,947건뿐이라
                  단지의 99%가 이름을 못 받고 주소 문자열로 떨어졌다.
                  연립다세대는 한 동짜리 집합건축물('3')이라 이름이 거기 있다
                  (regstr_kind_cd=3 의 54%가 bld_nm 보유).
                  전유부('4')는 쓰지 않는다 — root_bldrgst_pk 가 표제부를 가리켜
                  다단계 단지에서 단지의 root 와 어긋난다. */
               /* ★★ 2026-10-16 수정 — 여기에 MAX(bld_nm) 을 쓰고 있었다.
                  **문자열 MAX 는 사전순 마지막**을 집는다. 접두가 같으면 긴 쪽이 이긴다:

                    "돈암동 삼성아파트"      <  "돈암동 삼성아파트 유치원동"
                    "창신쌍용아파트 2지구"   <  "창신쌍용아파트 2지구 상가"

                  그래서 736세대 단지가 '유치원동', 1,006세대 단지가 '상가' 로 떴다.
                  숫자는 맞고 이름만 틀려서 **집계로는 안 드러나고 화면에서만 보였다.**

                  정책 7장이 이미 적어둔 규칙이다 — "컬럼별 MAX 는 서로 다른 행의 값을
                  한 줄에 섞는다. TOP 1 ... ORDER BY 로 한 건을 통째로 집는다"(CONTEXT 4-16).
                  인허가에서 배운 교훈인데 단지명에는 적용돼 있지 않았다.

                  -> 대장 종류 우선순위(총괄 > 집합 > 일반)는 그대로 두고, 같은 종류
                     안에서는 **세대수가 가장 많은 표제부**를 집는다. 세대가 모두 0이면
                     연면적으로 가른다. 부속동(유치원·상가·경비실)은 세대와 면적이
                     작으므로 **키워드 목록 없이 자동으로 밀린다** — 이름을 열거해
                     거르면 새로운 부속동 이름이 나올 때마다 또 틀린다. */
               nm.bld_nm,
               nm.nm_src,
               MAX(b.sigungu_cd), MAX(b.bjdong_cd),
               CASE WHEN MAX(CASE WHEN b.regstr_kind_cd='1' THEN 1 ELSE 0 END) = 1
                    THEN 'RECAP' ELSE 'STANDALONE' END
        FROM silver.bld_basis_outline b
        /* 단지의 이름 후보를 한 건으로 집는다. 세대수는 표제부에 있으므로 조인한다. */
        OUTER APPLY (
            SELECT TOP 1
                   bld_nm = NULLIF(LTRIM(RTRIM(b2.bld_nm)),''),
                   nm_src = CASE b2.regstr_kind_cd WHEN '1' THEN 'RECAP'
                                                   WHEN '3' THEN 'TITLE'
                                                   ELSE 'GENERAL' END
            FROM silver.bld_basis_outline b2
            LEFT JOIN silver.bld_title t2
                   ON t2.mgm_bldrgst_pk = b2.mgm_bldrgst_pk AND t2.is_current = 1
            WHERE b2.is_current = 1
              AND b2.regstr_kind_cd IN ('1','2','3')
              AND b2.root_bldrgst_pk = b.root_bldrgst_pk
              AND NULLIF(LTRIM(RTRIM(b2.bld_nm)),'') IS NOT NULL
            ORDER BY CASE b2.regstr_kind_cd WHEN '1' THEN 1 WHEN '3' THEN 2 ELSE 3 END,
                     ISNULL(t2.hhld_cnt, 0) DESC,      -- 세대가 많은 동이 단지를 대표한다
                     ISNULL(t2.tot_area, 0) DESC,      -- 세대가 모두 0이면 연면적으로
                     b2.mgm_bldrgst_pk                 -- 그래도 같으면 고정 순서로 (재현성)
        ) nm
        WHERE b.is_current = 1
          AND b.regstr_kind_cd IN ('1','2','3')      -- 전유부 제외
          AND b.root_bldrgst_pk IS NOT NULL
          AND (@sigungu_cd IS NULL OR b.sigungu_cd = @sigungu_cd)
          AND (@bjdong_cd  IS NULL OR b.bjdong_cd  = @bjdong_cd)
        GROUP BY b.root_bldrgst_pk, nm.bld_nm, nm.nm_src;

    OPEN cur;
    FETCH NEXT FROM cur INTO @iv, @nm, @nmsrc, @sgg, @bjd, @rule;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC gold.usp_resolve_complex 'ROOT_PK', @iv, @nm, @nmsrc, @sgg, @bjd, @rule, @iv,
             @complex_id = @id OUTPUT;
        FETCH NEXT FROM cur INTO @iv, @nm, @nmsrc, @sgg, @bjd, @rule;
    END
    CLOSE cur; DEALLOCATE cur;

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
