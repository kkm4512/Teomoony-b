/* ============================================================
   120_exar_eunpyeong : 전유공용면적을 은평구 전체로 (2026-10-18)

   장위동·수색동으로 축을 검증했다. 이제 은평구(11380) 11개 법정동 전부.
   실측 기준 176,552호 x 6.95건 / 100건 = 약 12,271콜 (80콜/분 -> 약 2시간 30분).

   ★ 수색동 행(target 6)을 같이 끈다.
     v_load_plan 은 `t.bjdong_cd IS NULL OR RIGHT(lawd_cd,5)=t.bjdong_cd` 로
     펼친다. 은평 전체 행에 exar 를 붙이는 순간 수색동이 **두 번** 잡힌다.
     지우지 않고 끈다 - 지우면 "왜 따로 있었는지" 가 같이 사라진다.
   ============================================================ */
USE Teomoony;
GO
SET NOCOUNT ON;
GO

PRINT '--- 바꾸기 전 ---';
SELECT target_id, sgg_cd, bjdong_cd, ops, enabled, note FROM meta.load_target ORDER BY target_id;
GO

UPDATE meta.load_target
   SET ops = 'base,ext,pms,exar',
       note = N'은평구 (2026-10-18 exar 추가 - 전유공용면적 전 법정동)'
 WHERE sgg_cd = '11380' AND bjdong_cd IS NULL AND enabled = 1;
PRINT '  은평구 전체 행에 exar 추가';
GO

UPDATE meta.load_target
   SET enabled = 0,
       note = N'수색동 exar 단독 행. 2026-10-18 은평구 전체 행이 exar 를 품으면서 '
            + N'중복이 되어 끈다(끄기 전 적재 완료). 남겨 두는 이유: 축을 처음 '
            + N'검증할 때 수색동만 따로 올렸다는 사실이 여기서만 읽힌다.'
 WHERE sgg_cd = '11380' AND bjdong_cd = '10100' AND ops = 'exar';
PRINT '  수색동 단독 행 끔 (중복 방지)';
GO

PRINT '--- 바꾼 뒤 ---';
SELECT target_id, sgg_cd, bjdong_cd, ops, enabled, note FROM meta.load_target ORDER BY target_id;
GO

PRINT '--- ★ 이번에 돌 단위 (area 그룹, TODO/RETRY 만) ---';
SELECT 상태, 단위수 = COUNT(*)
  FROM meta.v_load_plan WHERE grp = 'area'
 GROUP BY 상태 ORDER BY 1;
GO

PRINT '--- 법정동별 ---';
SELECT lawd_cd, 법정동, 상태, 선행
  FROM meta.v_load_plan WHERE grp = 'area'
 ORDER BY 상태, lawd_cd;
GO
