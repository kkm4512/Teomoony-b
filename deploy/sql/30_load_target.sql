SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* ============================================================
   30_load_target : 적재 목표를 선언하고, 할 일은 계산한다 — 2026-10-17

   왜 만드나
   ------------------------------------------------------------
   지금까지 범위를 넓히려면 사람이 명령을 일곱 번 쳤다. 지역이 늘면
   선형으로 는다. 그런데 **무엇이 끝났는지는 DB 가 이미 안다**
   (meta.ingest_run, 정책 6장). 그러니 사람이 적을 것은 "할 일" 이 아니라
   **"어디까지 갖고 싶은가"** 뿐이다. 할 일은 목표 - 완료 로 계산한다.

   ★ 덤으로 화면의 빈칸 어휘가 정확해진다.
     지금 SCOPE(아직 적재 전) 는 **"넣을 생각이 없는 곳"과 "넣을 건데 아직인 곳"
     을 구분하지 못한다.** 목표에 있으면 '예정', 없으면 '대상 아님' 이다.

   경계
   ------------------------------------------------------------
   건축물대장 7종만 법정동 단위로 meta.ingest_run 에 남는다(적재기가 기록).
   지적·건물·실거래·K-apt·관리비는 기록이 없어 **여기서 판정하지 않는다** —
   러너가 대상 테이블 유무로 거칠게 본다. 모르는 것을 아는 척하지 않는다.
   ============================================================ */
USE Teomoony;
GO

/* ---------- op 카탈로그 : 별칭 <-> 실제 operation ----------
   파이썬과 SQL 이 같은 표를 보게 한다. 양쪽에 따로 적으면 반드시 어긋난다. */
IF OBJECT_ID('meta.load_op') IS NULL
CREATE TABLE meta.load_op (
    op_alias   VARCHAR(20)  NOT NULL PRIMARY KEY,
    operation  VARCHAR(60)  NOT NULL UNIQUE,
    grp        VARCHAR(10)  NOT NULL,    -- base | ext | pms
    sort_no    INT          NOT NULL,
    note       NVARCHAR(100) NULL
);
GO
/* ★ 서비스가 둘이 되었다 (2026-10-17).
   건축인허가(ArchPmsHubService)는 건축물대장(BldRgstHubService)과 **다른 서비스**다.
   활용신청도 따로 받고 일일 한도도 따로 센다. 그런데 run_plan 의 api_source
   선등록은 domain 을 'BLDRGST' 로, base_url 을 BldRgstHubService 로 **박아 두고**
   있었다. 인허가 op 를 이 표에 넣는 순간 (BLDRGST, getApBasisOulnInfo) 라는
   **없는 서비스의 행**이 하나 생긴다.
   그래서 domain/base_url 도 이 표가 들고 있는다 - 파이썬과 SQL 이 같은 표를
   보게 한다는 원칙 그대로다. */
IF COL_LENGTH('meta.load_op','domain') IS NULL
    ALTER TABLE meta.load_op ADD domain VARCHAR(20) NOT NULL
          CONSTRAINT df_load_op_domain DEFAULT 'BLDRGST';
GO
IF COL_LENGTH('meta.load_op','base_url') IS NULL
    ALTER TABLE meta.load_op ADD base_url VARCHAR(300) NULL;
GO
MERGE meta.load_op AS t
USING (VALUES
    ('basis','getBrBasisOulnInfo' ,'base',1,'BLDRGST','BldRgstHubService',N'기본개요 — 계층의 단일 진실 공급원'),
    ('title','getBrTitleInfo'     ,'base',2,'BLDRGST','BldRgstHubService',N'표제부(동)'),
    ('recap','getBrRecapTitleInfo','base',3,'BLDRGST','BldRgstHubService',N'총괄표제부(단지)'),
    ('atch' ,'getBrAtchJibunInfo' ,'base',4,'BLDRGST','BldRgstHubService',N'부속지번'),
    ('flr'  ,'getBrFlrOulnInfo'   ,'ext' ,5,'BLDRGST','BldRgstHubService',N'층별개요'),
    ('expos','getBrExposInfo'     ,'ext' ,6,'BLDRGST','BldRgstHubService',N'전유부(호)'),
    ('hsprc','getBrHsprcInfo'     ,'ext' ,7,'BLDRGST','BldRgstHubService',N'주택가격 — 분량의 60%를 먹는다'),
    /* 건축인허가 - 대장이 "지어진 것"이면 인허가는 "지으려는 것"이다.
       신축은 거래가 먼저 일어나고 대장이 나중에 생긴다. 그 시차를 메운다. */
    ('pms'    ,'getApBasisOulnInfo','pms',8,'ARCHPMS','ArchPmsHubService',N'인허가 기본개요'),
    ('pmsdong','getApDongOulnInfo' ,'pms',9,'ARCHPMS','ArchPmsHubService',N'인허가 동별개요')
) AS s(op_alias,operation,grp,sort_no,domain,svc,note)
   ON t.op_alias = s.op_alias
WHEN MATCHED THEN UPDATE SET operation=s.operation, grp=s.grp, sort_no=s.sort_no,
                             domain=s.domain, note=s.note,
                             base_url='https://apis.data.go.kr/1613000/'+s.svc+'/'+s.operation
WHEN NOT MATCHED THEN INSERT (op_alias,operation,grp,sort_no,domain,base_url,note)
     VALUES (s.op_alias,s.operation,s.grp,s.sort_no,s.domain,
             'https://apis.data.go.kr/1613000/'+s.svc+'/'+s.operation, s.note);
GO

/* ---------- 목표 ---------- */
IF OBJECT_ID('meta.load_target') IS NULL
CREATE TABLE meta.load_target (
    target_id  INT IDENTITY(1,1) PRIMARY KEY,
    sgg_cd     CHAR(5)      NOT NULL,
    bjdong_cd  CHAR(5)      NULL,          -- NULL = 시군구 전체
    ops        VARCHAR(200) NOT NULL
               DEFAULT 'base,ext',          -- 별칭 또는 그룹(base/ext) 쉼표 구분
    priority   INT          NOT NULL DEFAULT 100,
    enabled    BIT          NOT NULL DEFAULT 1,
    note       NVARCHAR(200) NULL,
    created_at DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()
);
GO
/* UNIQUE 는 NULL 끼리도 같다고 보므로 시군구 전체 목표는 자연히 하나만 남는다 */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='uq_load_target')
CREATE UNIQUE INDEX uq_load_target ON meta.load_target (sgg_cd, bjdong_cd);
GO

/* ---------- 할 일 = 목표 x 법정동 x op  -  이미 OK ----------
   ★ 상태를 세 가지로만 적는다. 정책 6장의 어휘와 같은 규칙이다.
       DONE     그 법정동에서 status='OK' 로 끝난 기록이 있다
       RETRY    돌린 적은 있는데 OK 가 아니다 (PARTIAL/FAIL/RUNNING)
       TODO     돌린 적이 없다
   RETRY 를 TODO 와 섞지 않는 이유 — **끊긴 적재와 안 해본 적재는 다른 문제다.**
   끊긴 쪽은 원인이 있을 수 있어 사람이 봐야 한다.                       */
IF OBJECT_ID('meta.v_load_plan') IS NOT NULL DROP VIEW meta.v_load_plan;
GO
CREATE VIEW meta.v_load_plan
AS
WITH tgt AS (
    SELECT t.target_id, t.priority, t.ops,
           l.lawd_cd, l.emd_nm, sgg_cd = t.sgg_cd, bjdong_cd = RIGHT(l.lawd_cd, 5)
    FROM meta.load_target t
    JOIN meta.lawd_code l
      ON l.sgg_cd = t.sgg_cd
     AND (t.bjdong_cd IS NULL OR RIGHT(l.lawd_cd, 5) = t.bjdong_cd)
    WHERE t.enabled = 1
),
want AS (
    SELECT tgt.*, o.op_alias, o.operation, o.grp, o.sort_no
    FROM tgt
    JOIN meta.load_op o
      ON ',' + REPLACE(tgt.ops, ' ', '') + ','
         LIKE '%,' + o.op_alias + ',%'
      OR ',' + REPLACE(tgt.ops, ' ', '') + ','
         LIKE '%,' + o.grp + ',%'
),
runs AS (
    SELECT scope_key = r.scope_key, s.operation,
           ok_cnt  = SUM(CASE WHEN r.status = 'OK' THEN 1 ELSE 0 END),
           any_cnt = COUNT(*),
           last_at = MAX(r.started_at),
           last_status = MAX(CASE WHEN r.status='OK' THEN 'OK' ELSE r.status END)
    FROM meta.ingest_run r
    JOIN meta.api_source s ON s.source_id = r.source_id
    /* ★ 번지 하나만 떠본 기록은 법정동 적재가 아니다 (2026-10-17).
       scope_key 는 `시군구/법정동` 인데, --bun 을 줘서 **한 번지만** 떠본
       probe 도 같은 스코프로 남는다(run_mode='SINGLE'). 그러면 그 법정동 전체가
       DONE 으로 보이고 러너는 **영원히 건너뛴다.** 필드 확인용으로 번지 하나를
       떠보는 일은 흔하다 - 인허가 필드도 장위동 62-1 로 확인했다.
       '적재했다' 로 셀 수 있는 것은 FULL 뿐이다. */
    WHERE r.run_mode <> 'SINGLE'
    GROUP BY r.scope_key, s.operation
)
SELECT w.sgg_cd, w.bjdong_cd, w.lawd_cd, 법정동 = w.emd_nm,
       w.op_alias, w.operation, w.grp, w.priority, w.sort_no,
       상태 = CASE WHEN ISNULL(x.ok_cnt,0) > 0 THEN 'DONE'
                   WHEN ISNULL(x.any_cnt,0) > 0 THEN 'RETRY'
                   ELSE 'TODO' END,
       /* ★ 선행 조건 (2026-10-17 추가).
          기본개요가 계층의 단일 진실 공급원이다. 표제부·총괄·부속지번·층별·
          전유부·주택가격은 전부 그 아래에 매달린다. 기본개요 없이 먼저 넣으면
          **깨지지는 않지만 붕 뜬 채로 쌓이고**, 그 사이에 단지를 묶으면
          그 동들이 빠진 채로 단지가 생긴다.

          실제로 그랬다 — `go --ops title` 이 은평구 법정동코드를 채우면서
          새로 잡힌 11개 법정동에 **기본개요보다 표제부를 먼저** 넣었다.
          --ops 로 축을 골라 돌릴 수 있게 해 놓고 순서는 안 막아 둔 탓이다. */
       선행 = CASE
                   /* ★ 인허가는 대장과 **다른 계통**이다 (2026-10-17).
                      mgmPmsrgstPk -> mgmDongOulnPk 로 자기들끼리 매달린다. 대장
                      기본개요를 기다릴 이유가 없다. 대신 **동별개요는 인허가
                      기본개요 아래에** 매달리므로 그쪽을 선행으로 둔다 -
                      표제부를 기본개요보다 먼저 넣었던 실수를 되풀이하지 않는다. */
                   WHEN w.op_alias IN ('basis','pms') THEN 'OK'
                   WHEN EXISTS (SELECT 1 FROM runs b
                                 WHERE b.scope_key = w.sgg_cd + '/' + w.bjdong_cd
                                   AND b.operation = CASE WHEN w.grp = 'pms'
                                        THEN 'getApBasisOulnInfo'
                                        ELSE 'getBrBasisOulnInfo' END
                                   AND b.ok_cnt > 0) THEN 'OK'
                   WHEN w.grp = 'pms' THEN 'PMS_MISSING'
                   ELSE 'BASIS_MISSING' END,
       마지막시각 = x.last_at,
       마지막상태 = x.last_status
FROM want w
LEFT JOIN runs x
       ON x.scope_key = w.sgg_cd + '/' + w.bjdong_cd
      AND x.operation = w.operation;
GO

/* ---------- 한눈에 보는 진도 ---------- */
IF OBJECT_ID('meta.v_load_progress') IS NOT NULL DROP VIEW meta.v_load_progress;
GO
CREATE VIEW meta.v_load_progress
AS
SELECT sgg_cd, op_alias, grp,
       법정동수 = COUNT(*),
       완료 = SUM(CASE WHEN 상태='DONE'  THEN 1 ELSE 0 END),
       재시도 = SUM(CASE WHEN 상태='RETRY' THEN 1 ELSE 0 END),
       남음 = SUM(CASE WHEN 상태='TODO'  THEN 1 ELSE 0 END),
       선행미완 = SUM(CASE WHEN 상태 <> 'DONE' AND 선행 <> 'OK' THEN 1 ELSE 0 END)
FROM meta.v_load_plan
GROUP BY sgg_cd, op_alias, grp;
GO

PRINT '30_load_target done.';
GO
