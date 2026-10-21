/* ============================================================
   32_exar_targets : 전유공용면적을 **장위동 · 수색동에만** 건다  2026-10-18

   ★ 왜 두 동인가
     전체(종로+성북+은평)는 호 273,789 x 6.95 = 약 190만 건 / 19,000 호출이다
     (돈암동 636번지 실측 7,658건 / 1,102호 기준). 일일 한도 10,000 이니 이틀치다.
     먼저 두 동으로 **쓸모를 확인**하고 범위를 넓힌다. 두 동에 테스트단지가
     하나씩 있다 — 장위동 49101(래미안 장위 퍼스트하이), 수색동 103835
     (DMC 롯데캐슬 더 퍼스트). 화면 검증이 바로 된다.
     예상: 장위 15,365호 + 수색 8,405호 = 23,770호 -> 약 165,000건 / 1,650 호출.

   ★ 은평은 시군구 전체 목표(11380/NULL)다 — 거기 exar 를 넣으면 11개 법정동이
     다 돈다. 그래서 수색동만 **법정동 단위 행을 따로** 만든다. ops 가 겹치지
     않으므로(기존 base,ext,pms / 새 exar) v_load_plan 에서 중복되지 않는다.
   ============================================================ */
USE Teomoony;
GO
SET NOCOUNT ON;
GO

PRINT '--- 전 ---';
SELECT target_id, sgg_cd, bjdong_cd, ops, enabled, note
  FROM meta.load_target ORDER BY sgg_cd, bjdong_cd;

/* 장위동: 기존 행에 축만 더한다 */
UPDATE meta.load_target
   SET ops = 'base,ext,pms,exar'
 WHERE sgg_cd = '11290' AND bjdong_cd = '13800';

/* 수색동: 은평 전체 행을 건드리지 않으려고 법정동 행을 따로 둔다 */
MERGE meta.load_target AS t
USING (SELECT '11380' AS sgg_cd, '10100' AS bjdong_cd) AS s
   ON t.sgg_cd = s.sgg_cd AND t.bjdong_cd = s.bjdong_cd
WHEN MATCHED THEN UPDATE SET ops = 'exar', enabled = 1
WHEN NOT MATCHED THEN INSERT (sgg_cd, bjdong_cd, ops, priority, note)
     VALUES (s.sgg_cd, s.bjdong_cd, 'exar', 100,
             N'수색동 - 전유공용면적만 (테스트단지 103835 DMC 롯데캐슬). 은평 전체 행과 별개');

PRINT '--- 후 ---';
SELECT target_id, sgg_cd, bjdong_cd, ops, enabled, note
  FROM meta.load_target ORDER BY sgg_cd, bjdong_cd;
GO

PRINT '--- area 그룹 계획 (이것만 돈다) ---';
SELECT sgg_cd, bjdong_cd, 법정동, op_alias, 상태, 선행
  FROM meta.v_load_plan WHERE grp = 'area' ORDER BY sgg_cd, bjdong_cd;
PRINT '  두 줄만 나와야 한다. 더 나오면 범위가 샌 것이다.';
GO

PRINT '--- 중복 점검: 같은 (법정동, op) 가 두 번 나오지 않는가 ---';
SELECT sgg_cd, bjdong_cd, op_alias, n = COUNT(*)
  FROM meta.v_load_plan GROUP BY sgg_cd, bjdong_cd, op_alias HAVING COUNT(*) > 1;
PRINT '  행이 없어야 정상이다.';
GO
