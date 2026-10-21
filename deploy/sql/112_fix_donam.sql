/* ============================================================
   112_fix_donam : 107 이 등록한 법정동을 바로잡는다  2026-10-18

   ★ 무엇이 틀렸나
     107 에서 '돈암동 = 11290/10700' 으로 등록했다. **추측이었고 틀렸다.**
     실측(111): 돈암동은 **11290/10300** 이다. 10700 은 다른 동이다.
     코드는 이름으로 추측하지 않는다 — 정책 7장이 말하는 그 자리다.

   ★ 10700 은 지우지 않고 끈다(enabled=0)
     지우면 "왜 여기 있었나" 가 같이 사라진다. 끄고 사유를 note 에 남긴다.
   ============================================================ */
USE Teomoony;
GO
SET NOCOUNT ON;
GO

PRINT '--- 전 ---';
SELECT target_id, sgg_cd, bjdong_cd, ops, enabled, note
  FROM meta.load_target ORDER BY sgg_cd, bjdong_cd;

/* 잘못 넣은 10700 을 끈다 */
UPDATE meta.load_target
   SET enabled = 0,
       note = N'2026-10-18 Claude 오등록(돈암동을 10700 으로 추측). 실제 돈암동은 10300.'
 WHERE sgg_cd='11290' AND bjdong_cd='10700';

/* 진짜 돈암동 */
MERGE meta.load_target AS t
USING (SELECT '11290' AS sgg_cd, '10300' AS bjdong_cd) AS s
   ON t.sgg_cd = s.sgg_cd AND t.bjdong_cd = s.bjdong_cd
WHEN MATCHED THEN UPDATE SET ops='base,ext', enabled=1
WHEN NOT MATCHED THEN INSERT (sgg_cd, bjdong_cd, ops, priority, note)
     VALUES (s.sgg_cd, s.bjdong_cd, 'base,ext', 100,
             N'돈암동 - 전유부/층별/주택가격 (테스트단지 57232 브라운스톤 돈암)');

PRINT '--- 후 ---';
SELECT target_id, sgg_cd, bjdong_cd, ops, enabled, note
  FROM meta.load_target ORDER BY sgg_cd, bjdong_cd;
GO

PRINT '--- 돈암동(10300) 계획 ---';
SELECT op_alias, 상태, 선행, 마지막상태, 마지막시각
  FROM meta.v_load_plan WHERE sgg_cd='11290' AND bjdong_cd='10300' ORDER BY op_alias;
GO

PRINT '--- 꺼진 10700 이 계획에서 빠졌나 (행이 없어야 정상) ---';
SELECT op_alias, 상태 FROM meta.v_load_plan
 WHERE sgg_cd='11290' AND bjdong_cd='10700';
GO
