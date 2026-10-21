/* ============================================================
   107_add_donam : 돈암동(11290/10700)을 적재 목표에 올린다  2026-10-18

   ★ 왜 이 파일인가
     `py run_plan.py add` 가 하는 일은 meta.load_target 에 MERGE 하는 것
     하나뿐이다(run_plan.py cmd_add). 그래서 같은 MERGE 를 여기서 한다.
     감시(_job_runner)의 허용 목록은 인자를 받지 않는다 — 임의 인자를
     받게 만들면 그게 곧 원격 셸이 되기 때문이다. 대신 **인자를 파일에
     박아** 이미 허용된 sql 채널로 보낸다. 무엇이 등록되는지가 이 파일에
     그대로 남으므로 나중에 읽어도 알 수 있다.

   ★ 왜 돈암동 하나인가  (2026-10-18 판단)
     · 지금 막힌 것은 테스트단지 57232(브라운스톤 돈암)의 전유부다.
       실측 1,102행 — 10-16 이후 한 발도 못 나갔다. 돈암동이면 충족된다.
     · 성북 39동 전체는 README 의 '적재 범위 넓히기' 로 따로 열려 있는
       별개 항목이다. 여기 끼워 넣을 일이 아니다.
     · 이어받기(--from-page 자동)는 오늘 아침 **한 번** 실전 검증됐다.
       수천 단위로 키우기 전에 작은 것으로 한 번 더 본다.

   ★ 왜 ops 에 pms 를 빼는가
     돈암동 인허가를 더 받아도 **단지에 안 붙는다.** 허가가 합필 전
     지번으로 들어오는 문제(CONTEXT 10-6 의 ②)가 아직 안 풀렸다.
     그걸 먼저 풀고 받는 것이 순서다.

   되돌리려면: UPDATE meta.load_target SET enabled=0
                WHERE sgg_cd='11290' AND bjdong_cd='10700';
   ============================================================ */
USE Teomoony;
GO
SET NOCOUNT ON;
GO

PRINT '--- 전 ---';
SELECT target_id, sgg_cd, bjdong_cd, ops, priority, enabled, note
  FROM meta.load_target ORDER BY priority, sgg_cd, bjdong_cd;

MERGE meta.load_target AS t
USING (SELECT '11290' AS sgg_cd, '10700' AS bjdong_cd) AS s
   ON t.sgg_cd = s.sgg_cd
  AND (t.bjdong_cd = s.bjdong_cd OR (t.bjdong_cd IS NULL AND s.bjdong_cd IS NULL))
WHEN MATCHED THEN UPDATE SET ops = 'base,ext', enabled = 1
WHEN NOT MATCHED THEN INSERT (sgg_cd, bjdong_cd, ops, priority, note)
     VALUES (s.sgg_cd, s.bjdong_cd, 'base,ext', 100,
             N'돈암동 - 전유부/층별/주택가격 (테스트단지 57232)');

PRINT '--- 후 ---';
SELECT target_id, sgg_cd, bjdong_cd, ops, priority, enabled, note
  FROM meta.load_target ORDER BY priority, sgg_cd, bjdong_cd;
GO

PRINT '--- 돈암동이 계획에 뜨나 (상태별) ---';
SELECT op_alias, 상태, 선행, 마지막상태, 마지막시각
  FROM meta.v_load_plan
 WHERE sgg_cd='11290' AND bjdong_cd='10700'
 ORDER BY op_alias;
PRINT '  base 가 DONE 이고 ext 쪽(flr/expos/hsprc)이 TODO 면 의도대로다.';
GO
