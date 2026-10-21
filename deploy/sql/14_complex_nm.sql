SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* ============================================================
   14_complex_nm : 단지명을 표제부에서도 가져온다

   ★ 문제 (2026-10-15 실측)
     단지 54,064 중 53,581 (99.1%) 이 이름 자리에 주소 문자열을 들고 있었다.
     "서울특별시 성북구 장위동 115번지" 같은 것. 그래서 연립다세대를 이름으로
     검색하면 안 나온다.

     원인은 두 가지가 겹친 것이다.

     ① 단지명을 총괄표제부(regstr_kind_cd='1')에서만 가져왔다.
        총괄표제부는 1,947건뿐인데 단지는 54,064개다.
        05_revise.sql 의 주석은 "총괄표제부 이름 > 아무 구성원의 이름" 이라고
        적혀 있었으나 뒷부분이 구현돼 있지 않았다. 의도와 코드가 어긋나 있었다.

     ② 주소 폴백이 complex_nm 에 직접 써버렸다.
        한 번 주소가 들어가면 complex_nm IS NULL 이 영영 거짓이고,
        usp_resolve_complex 도 COALESCE(@complex_nm, complex_nm) 이라
        나중에 진짜 이름이 생겨도 못 덮었다.

   ★ 이름이 어디에 있나 (is_current=1 기준 실측)

       regstr_kind_cd        건수      bld_nm 보유
       1 총괄표제부          1,947       479  (24.6%)
       2 일반건축물         50,576     4,584  ( 9.1%)
       3 집합건축물 표제부   9,636     5,218  (54.2%)   <- 연립다세대가 여기
       4 전유부            201,866   161,085  (79.8%)   <- 쓰지 않는다

     전유부를 쓰지 않는 이유: 전유부의 mgm_up_bldrgst_pk 는 표제부를 가리키므로
     root_bldrgst_pk 가 표제부 PK 가 된다. 총괄표제부가 있는 다단계 단지에서는
     단지의 root(총괄표제부 PK)와 어긋나 조인이 틀린다.

   ★ 단지코드는 바뀌지 않는다
     complex_identity 가 ROOT_PK 기준이라 usp_resolve_complex 가 기존 단지를
     다시 찾아 이름만 UPDATE 한다. 재구성해도 코드가 재현된다(README 5장).

   적용 후:
       python teomoony_ingest.py build --sigungu 11110
       python teomoony_ingest.py build --sigungu 11290
       python load_rtms.py --rematch-only
   ============================================================ */
USE Teomoony;
GO

/* ---- 이름의 출처를 기록한다 ---- */
IF COL_LENGTH('gold.complex', 'complex_nm_src') IS NULL
    ALTER TABLE gold.complex ADD complex_nm_src VARCHAR(10) NULL;
GO

/* 기존 행에 출처를 소급한다. 주소와 같으면 ADDR, 아니면 기존 규칙상 총괄표제부다.
   이걸 안 해두면 아래의 덮어쓰기 규칙이 NULL 을 만나 아무것도 못 고친다. */
UPDATE gold.complex
   SET complex_nm_src = CASE WHEN complex_nm = rep_plat_plc THEN 'ADDR' ELSE 'RECAP' END
 WHERE complex_nm_src IS NULL;
GO

CREATE OR ALTER PROCEDURE gold.usp_resolve_complex
    @identity_type  VARCHAR(20),
    @identity_val   VARCHAR(100),
    @complex_nm     NVARCHAR(200) = NULL,
    @complex_nm_src VARCHAR(10)   = NULL,   -- RECAP | TITLE | GENERAL | ADDR
    @sigungu_cd     CHAR(5)       = NULL,
    @bjdong_cd      CHAR(5)       = NULL,
    @grouping_rule  VARCHAR(30)   = NULL,
    @root_pk        VARCHAR(50)   = NULL,
    @complex_id     INT           OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /* ★ OUTPUT 변수는 호출자의 직전 값을 들고 들어온다.
       SELECT @x = ... 는 행이 없으면 변수를 그대로 둔다(NULL 로 만들지 않는다).
       초기화하지 않으면 두 번째 호출부터 직전 단지를 재사용해버린다. */
    SET @complex_id = NULL;

    SELECT @complex_id = complex_id
    FROM gold.complex_identity
    WHERE identity_type = @identity_type AND identity_val = @identity_val;

    IF @complex_id IS NOT NULL
    BEGIN
        /* ★ 이름 덮어쓰기 규칙
           예전에는 COALESCE(@complex_nm, complex_nm) 이라, 한 번 주소가 들어가면
           진짜 이름이 나중에 생겨도 영영 안 바뀌었다. 출처를 기록해 두고
           '주소였던 것' 은 비워서 끝의 폴백이 다시 돌게 한다. */
        UPDATE gold.complex
           SET complex_nm = CASE WHEN @complex_nm IS NOT NULL   THEN @complex_nm
                                 WHEN complex_nm_src = 'ADDR'   THEN NULL
                                 ELSE complex_nm END,
               complex_nm_src = CASE WHEN @complex_nm IS NOT NULL THEN @complex_nm_src
                                     WHEN complex_nm_src = 'ADDR' THEN NULL
                                     ELSE complex_nm_src END,
               updated_at = SYSDATETIME()
         WHERE complex_id = @complex_id;
        RETURN;
    END

    BEGIN TRAN;
        INSERT INTO gold.complex (root_bldrgst_pk, complex_nm, complex_nm_src,
                                   sigungu_cd, bjdong_cd, grouping_rule)
        VALUES (@root_pk, @complex_nm, @complex_nm_src, @sigungu_cd, @bjdong_cd, @grouping_rule);
        SET @complex_id = CAST(SCOPE_IDENTITY() AS INT);

        INSERT INTO gold.complex_identity (complex_id, identity_type, identity_val, is_primary)
        VALUES (@complex_id, @identity_type, @identity_val, 1);
    COMMIT;
END
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
