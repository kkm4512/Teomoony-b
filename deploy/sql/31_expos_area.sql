/* ============================================================
   31_expos_area : 전유공용면적을 축으로 올린다  2026-10-18

   ★ 기각했던 축이다. 왜 되살리나
     정책 4장이 기각한 사유는 **분량**이었다 —
       "호당 전유 1행 + 공용 N행 -> 응답의 80%가 공용, 지번당 수천 건"
     그 판단의 맥락은 '실거래를 동/호로 특정한다'(4-1)였고, 그건 지금도 불가다
     (실거래에 동·호가 없다). 그런데 **대장 쪽 용도는 다르다**:
       · 호 상세에 `전용면적` 칸이 지금 '해당 없음' 으로 비어 있다
       · 격자에 **평형 필터**를 못 건다 — 호별 면적이 없어서다
       · 실거래는 평형으로 묶이는데(4-1), 대장 쪽에 평형이 없어 **둘을 못 잇는다**
     즉 기각 사유(분량)는 그대로지만 **얻는 것이 그때와 다르다.**

   ★ 그래서 별도 그룹(grp='area')이다
     base/ext 에 넣으면 `go` 한 번에 딸려 들어가 한도를 통째로 먹는다.
     `--grp area` 로 **일부러 불러야** 돈다. pms 를 따로 둔 것과 같은 이유.

   ★ 분량은 **재고 나서** 정한다
     지번당 수천 건이라는 기록만 있고 법정동 단위 실측이 없다. 먼저 한 번지를
     probe 해서 totalCount 를 보고, 그 숫자로 범위를 정한다. 추측으로 며칠치
     한도를 쓰지 않는다.
   ============================================================ */
USE Teomoony;
GO
SET NOCOUNT ON;
GO

/* ---------- 1) 법정동으로 자를 수 있게 한다 ----------
   원래 테이블에는 sigungu_cd/bjdong_cd/pnu 가 없었다(적재 안 할 축이었으니까).
   없으면 '이 법정동을 받았나' 를 물을 수 없고, 러너의 이어받기 가드도 못 돈다. */
IF COL_LENGTH('silver.bld_expos_pubuse_area','sigungu_cd') IS NULL
    ALTER TABLE silver.bld_expos_pubuse_area ADD
        sigungu_cd CHAR(5) NULL, bjdong_cd CHAR(5) NULL,
        plat_gb_cd VARCHAR(1) NULL, bun VARCHAR(10) NULL, ji VARCHAR(10) NULL,
        bld_nm NVARCHAR(200) NULL, plat_plc NVARCHAR(300) NULL,
        regstr_gb_cd VARCHAR(2) NULL, regstr_kind_cd VARCHAR(2) NULL,
        etc_strct NVARCHAR(200) NULL,
        /* 층별개요와 같은 처리: 자연키가 같은 행이 여러 개면 면적을 합치고
           몇 개였는지 센다(collapse). 몇 개를 합쳤는지는 **적어 둔다**. */
        seg_cnt INT NULL;
GO
IF COL_LENGTH('silver.bld_expos_pubuse_area','pnu') IS NULL
    ALTER TABLE silver.bld_expos_pubuse_area ADD pnu CHAR(19) NULL;
GO

/* ---------- 2) 현재행 유일성 ----------
   ★ PK 필드가 **응답에 없다**(명세 실측 2026-10-18). mgmExposPubuseAreaPk 는
     건축인허가 쪽에만 있고 건축물대장 전유공용면적에는 없다. 그래서 자연키를
     직접 정한다 — 층별개요(24_flr_outline)가 같은 처지였고 같은 조합을 썼다.
     층·용도·구조까지 넣어야 한 호의 '전유 1 + 공용 N' 이 서로를 안 밀어낸다. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='uq_bld_expos_area_current')
CREATE UNIQUE INDEX uq_bld_expos_area_current
    ON silver.bld_expos_pubuse_area
       (mgm_bldrgst_pk, expos_pubuse_gb_cd, main_atch_gb_cd,
        flr_gb_cd, flr_no, main_purps_cd, strct_cd)
 WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_bld_expos_area_lawd')
CREATE INDEX ix_bld_expos_area_lawd
    ON silver.bld_expos_pubuse_area (sigungu_cd, bjdong_cd) WHERE is_current = 1;
GO

/* ---------- 3) op 등록 ---------- */
MERGE meta.load_op AS t
USING (VALUES
    ('exar','getBrExposPubuseAreaInfo','area',10,'BLDRGST','BldRgstHubService',
     N'전유공용면적 — 호별 전용면적. 분량이 크다(응답 80%가 공용). --grp area 로만 돈다')
) AS s(op_alias,operation,grp,sort_no,domain,svc,note)
   ON t.op_alias = s.op_alias
WHEN MATCHED THEN UPDATE SET operation=s.operation, grp=s.grp, sort_no=s.sort_no,
                             domain=s.domain, note=s.note,
                             base_url='https://apis.data.go.kr/1613000/'+s.svc+'/'+s.operation
WHEN NOT MATCHED THEN INSERT (op_alias,operation,grp,sort_no,domain,base_url,note)
     VALUES (s.op_alias,s.operation,s.grp,s.sort_no,s.domain,
             'https://apis.data.go.kr/1613000/'+s.svc+'/'+s.operation, s.note);
GO

PRINT '--- op 카탈로그 ---';
SELECT op_alias, grp, sort_no, domain, operation FROM meta.load_op ORDER BY sort_no;
PRINT '--- 전유공용면적 현재 행수 (0 이 정상 — 아직 안 받았다) ---';
SELECT 행수 = COUNT(*) FROM silver.bld_expos_pubuse_area WHERE is_current = 1;
GO
PRINT '31_expos_area done.';
GO
