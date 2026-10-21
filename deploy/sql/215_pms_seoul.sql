/* ============================================================
   215_pms_seoul : 건축허가(pms)를 서울 25구 전체로 (2026-10-20)

   사용자 답: 재개발 안양 원천 찾기는 "ㄴㄴ", 건축허가 서울 확대는 "ㅇㅇ".

   ★ 재 보니 건축허가는 서울 **3개 구**(11110 종로 · 11290 성북 · 11380 은평)
     57,449 건뿐이었다. `pms` 는 meta.load_op.grp 값이라 ops 에 'pms' 를 적으면
     그 그룹의 단계가 전부 켜진다(v_load_plan 이 op_alias 또는 grp 로 맞춘다).

   ★ 이 파일은 **계획만 바꾼다.** 지금 돌고 있는 chain-all 의 인자는
     `--ops title,jijigu,flr,expos,exar,hsprc` 라 pms 가 없다. 그래서 적재가
     저절로 시작되지 않는다 — 나중에 pms 단계를 따로 돌려야 한다.
     앞줄이 37시간 남았으므로 **지금 큐에 끼워 넣지 않는다.**

   ★ 안양(41171·41173)은 **일부러 제외한다.** 서울이 먼저 25구가 되고 나서
     같이 맞추는 게 순서다. 지금 안양에만 켜면 범위가 들쭉날쭉해진다.
     (214 에서 exar 는 서울과 같은 모양이라 바로 맞췄다 — 그건 서울이 이미 24구였다.)

   ★ 두 번 적용해도 안전하다 (NOT LIKE '%,pms,%').
   ============================================================ */
USE Teomoony;
GO
SET NOCOUNT ON;
GO

PRINT '--- 바꾸기 전: pms 가 켜진 행 ---';
SELECT target_id, sgg_cd, bjdong_cd, ops, enabled
  FROM meta.load_target
 WHERE ',' + REPLACE(ops, ' ', '') + ',' LIKE '%,pms,%'
 ORDER BY sgg_cd;
GO

UPDATE meta.load_target
   SET ops  = ops + ',pms',
       note = ISNULL(note + N' / ', N'')
            + N'2026-10-20 pms(건축허가) 추가 — 서울 25구로 확대'
 WHERE LEFT(sgg_cd, 2) = '11'
   AND enabled = 1
   AND ',' + REPLACE(ops, ' ', '') + ',' NOT LIKE '%,pms,%';
PRINT '  서울 행에 pms 추가';
GO

PRINT '--- 바꾼 뒤: 서울 행 전부 ---';
SELECT target_id, sgg_cd, bjdong_cd, ops, enabled
  FROM meta.load_target
 WHERE LEFT(sgg_cd, 2) = '11' AND enabled = 1
 ORDER BY sgg_cd;
GO

PRINT '--- 확인: 계획에 풀린 pms 단계의 서울 법정동 수 ---';
SELECT op_alias, 서울법정동 = COUNT(*),
       TODO = SUM(CASE WHEN 상태 = 'TODO' THEN 1 ELSE 0 END),
       DONE = SUM(CASE WHEN 상태 = 'DONE' THEN 1 ELSE 0 END),
       선행OK = SUM(CASE WHEN 선행 = 'OK' THEN 1 ELSE 0 END)
  FROM meta.v_load_plan
 WHERE LEFT(sgg_cd, 2) = '11' AND grp = 'pms'
 GROUP BY op_alias ORDER BY op_alias;
GO
