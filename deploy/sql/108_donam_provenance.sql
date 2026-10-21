/* ============================================================
   108_donam_provenance : 돈암동에 이미 있는 행이 **어디서 왔나**  2026-10-18

   ★ 왜 묻나
     run_plan 의 이어받기(2026-10-18 추가)는 "DB 행 수 / 100 = 받은 페이지 수"
     를 전제로 --from-page 를 계산한다. 이 전제는 그 행들이 **법정동 전체
     페이지네이션의 앞부분**일 때만 참이다.
     `--bun` 으로 번지 하나만 떠본 probe 행이 섞여 있으면 전제가 깨지고,
     건너뛴 페이지가 **구멍으로 남는다.** '동일' 과 달리 구멍은 안 보인다.
     (CONTEXT 10-2 — 번지 probe 가 법정동을 DONE 으로 만들던 그 함정의 사촌)

     그래서 돌리기 전에 밖에서 잰다.
   ============================================================ */
USE Teomoony;
GO
SET NOCOUNT ON;
GO

PRINT '--- 1. 돈암동(11290/10700) ext 축 현재 행 수 ---';
SELECT ax='expos', n=COUNT(*), 지번수=COUNT(DISTINCT pnu)
  FROM silver.bld_expos WHERE is_current=1 AND sigungu_cd='11290' AND bjdong_cd='10700'
UNION ALL SELECT 'flr', COUNT(*), COUNT(DISTINCT pnu)
  FROM silver.bld_flr_outline WHERE is_current=1 AND sigungu_cd='11290' AND bjdong_cd='10700'
UNION ALL SELECT 'hsprc', COUNT(*), COUNT(DISTINCT pnu)
  FROM silver.bld_hsprc WHERE is_current=1 AND sigungu_cd='11290' AND bjdong_cd='10700';
PRINT '  지번수가 1~2 뿐이면 번지 probe 다 -> 이어받기를 쓰면 안 된다.';
GO

PRINT '--- 2. 적재 기록 (run_mode 포함. SINGLE 이 섞였나) ---';
SELECT operation, run_mode, status, req_count, row_count, started_at,
       LEFT(ISNULL(err_msg,''),60) AS err
  FROM meta.ingest_run
 WHERE scope_key = '11290/10700'
 ORDER BY started_at;
PRINT '  행이 없는데 위에 데이터가 있으면 = 기록 밖에서 들어온 것이다.';
GO

PRINT '--- 3. 비교군: 장위동(11290/13800) 같은 축 ---';
SELECT ax='expos', n=COUNT(*), 지번수=COUNT(DISTINCT pnu)
  FROM silver.bld_expos WHERE is_current=1 AND sigungu_cd='11290' AND bjdong_cd='13800'
UNION ALL SELECT 'flr', COUNT(*), COUNT(DISTINCT pnu)
  FROM silver.bld_flr_outline WHERE is_current=1 AND sigungu_cd='11290' AND bjdong_cd='13800'
UNION ALL SELECT 'hsprc', COUNT(*), COUNT(DISTINCT pnu)
  FROM silver.bld_hsprc WHERE is_current=1 AND sigungu_cd='11290' AND bjdong_cd='13800';
GO
