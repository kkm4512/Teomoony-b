/* 167. 지역지구구역 (건축HUB getBrJijiguInfo) (2026-10-19)

   ★ 왜 넣나
     어제 VWorld 로 용도지역 폴리곤을 올렸다(11-40). 이건 그 **대장 쪽 짝**이다.
     `mgmBldrgstPk` 가 붙어 있어 **PK 로 1:1** 이고, `jijiguCdNm` 이 VWorld 의
     `uname` 과 **같은 어휘**("제2종일반주거지역")다. 두 축을 교차검증할 수 있다.
     땅으로 잰 것(공간교차)과 대장이 적어 둔 것이 어긋나면 그게 신호다.

   ★ 세 종류가 같이 온다 — 용도지역코드 / 용도지구코드 / 용도구역코드.
     `jijigu_gb_cd` 로 갈린다. 용도'지역'만 쓰려면 걸러야 한다.

   ★ 분량 (실측): 장위동 2,819 · 불광동 3,237 · 돈암동 472 · 사직동 220.
     페이지 상한은 **100** 이다(건축HUB 공통).
*/
IF OBJECT_ID('silver.bld_jijigu') IS NULL
CREATE TABLE silver.bld_jijigu (
    jijigu_sk       BIGINT IDENTITY(1,1) NOT NULL,
    mgm_bldrgst_pk  VARCHAR(50)    NOT NULL,
    sigungu_cd      CHAR(5)        NULL,
    bjdong_cd       CHAR(5)        NULL,
    plat_gb_cd      VARCHAR(1)     NULL,
    bun             VARCHAR(10)    NULL,
    ji              VARCHAR(10)    NULL,
    pnu             CHAR(19)       NULL,
    plat_plc        NVARCHAR(300)  NULL,
    new_plat_plc    NVARCHAR(400)  NULL,
    splot_nm        NVARCHAR(100)  NULL,
    block           NVARCHAR(40)   NULL,
    lot             NVARCHAR(40)   NULL,
    jijigu_gb_cd    VARCHAR(4)     NOT NULL,   -- 1 지역 / 2 지구 / 3 구역
    jijigu_gb_nm    NVARCHAR(40)   NULL,       -- 용도지역코드 / 용도지구코드 / 용도구역코드
    jijigu_cd       VARCHAR(20)    NOT NULL,   -- UQA122 ...
    jijigu_nm       NVARCHAR(100)  NULL,       -- 제2종일반주거지역 ...
    repr_yn         VARCHAR(1)     NULL,       -- 대표 여부
    etc_jijigu      NVARCHAR(200)  NULL,
    crtn_day        CHAR(8)        NULL,
    row_hash        BINARY(32)     NOT NULL,
    src_run_id      BIGINT         NULL,
    valid_from      DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    valid_to        DATETIME2(0)   NOT NULL DEFAULT '9999-12-31',
    is_current      BIT            NOT NULL DEFAULT 1,
    CONSTRAINT pk_bld_jijigu PRIMARY KEY CLUSTERED (jijigu_sk)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='uq_jijigu_current')
CREATE UNIQUE INDEX uq_jijigu_current ON silver.bld_jijigu
    (mgm_bldrgst_pk, jijigu_gb_cd, jijigu_cd) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_jijigu_pnu')
CREATE INDEX ix_jijigu_pnu ON silver.bld_jijigu (pnu)
    INCLUDE (jijigu_gb_cd, jijigu_nm) WHERE is_current = 1;
GO

/* op 카탈로그에 등록. ★ 여기 넣는 것만으로는 안 돈다 —
   meta.load_target.ops 에 별칭이 들어가야 계획에 잡힌다(v_load_plan 이 그렇게 짠다).
   그래서 아래에서 목표에도 붙인다. */
MERGE meta.load_op AS t
USING (VALUES
    ('jijigu','getBrJijiguInfo','ext',10,'BLDRGST','BldRgstHubService',
     N'지역지구구역 — 용도지역·지구·구역, PK 1:1')
) AS s(op_alias,operation,grp,sort_no,domain,svc,note)
   ON t.op_alias = s.op_alias
WHEN MATCHED THEN UPDATE SET operation=s.operation, grp=s.grp, sort_no=s.sort_no,
                             domain=s.domain, note=s.note,
                             base_url='https://apis.data.go.kr/1613000/'+s.svc+'/'+s.operation
WHEN NOT MATCHED THEN INSERT (op_alias,operation,grp,sort_no,domain,base_url,note)
     VALUES (s.op_alias,s.operation,s.grp,s.sort_no,s.domain,
             'https://apis.data.go.kr/1613000/'+s.svc+'/'+s.operation, s.note);
GO

/* 켜져 있는 목표에 별칭을 붙인다. 이미 있으면 그대로 둔다(두 번 붙지 않게). */
UPDATE meta.load_target
   SET ops = ops + ',jijigu'
 WHERE enabled = 1
   AND ',' + REPLACE(ops, ' ', '') + ',' NOT LIKE '%,jijigu,%';
PRINT CONCAT('  목표에 jijigu 를 붙인 행 = ', @@ROWCOUNT);
GO

SELECT op_alias, operation, grp, sort_no FROM meta.load_op ORDER BY sort_no;
SELECT target_id, sgg_cd, bjdong_cd, enabled, ops FROM meta.load_target WHERE enabled = 1;
