/* ============================================================
   214_anyang_scope : 경기 안양을 서울과 같은 범위로 (2026-10-20)

   사용자: "경기 안양은 내가 특수하게 넣은거라 유지하면되고 거기에도
            학교 유치원 상권 실거래가 같은 데이터가 다 있어야해"

   ★ 재 보니 안양(41171 만안 · 41173 동안)의 load_target.ops 가 'base,ext' 에
     멈춰 있었다. `exar`(전유공용면적)는 **그룹이 아니라 이름을 직접 적어야**
     켜지는 별칭이다(meta.load_op.grp 는 base|ext|pms). 서울 24개 행은
     'base,ext,exar' 인데 안양만 exar 가 빠져 있었다. 그래서 지금 돌고 있는
     (5/6) exar 단계의 장부에 **안양 법정동이 0** 이다.

   ★ 이 파일은 `exar` 만 켠다. `pms`(건축허가)는 **일부러 손대지 않는다** -
     서울조차 3개 구(종로·성북·은평)밖에 안 켜져 있어서, 안양에만 켜면
     "서울보다 안양이 더 채워진" 이상한 모양이 된다. 범위를 넓히는 건
     사용자가 결정할 일이다.

   ★ 중복 위험 없음: 120_exar_eunpyeong.sql 에서 은평은 '시군구 전체 행' 과
     '수색동 단독 행' 이 겹쳐 수색동이 두 번 잡혔다. 안양은 load_target 에
     bjdong_cd IS NULL 인 두 행뿐이라(실측) 그 문제가 없다.

   ★ 지금 돌고 있는 exar 는 시작할 때 법정동 목록을 이미 고정했다. 그래서
     이 변경은 **다음 exar 실행**부터 반영된다. 이번 회차의 구멍 보고에는
     안양이 '덜 받음' 으로 보일 수 있다 - 그건 이 변경 때문이고 고장이 아니다.
   ============================================================ */
USE Teomoony;
GO
SET NOCOUNT ON;
GO

PRINT '--- 바꾸기 전: 안양 ---';
SELECT target_id, sgg_cd, bjdong_cd, ops, enabled, note
  FROM meta.load_target WHERE sgg_cd IN ('41171','41173') ORDER BY target_id;
GO

/* 안양에 exar 를 더한다. 서울 표준('base,ext,exar')과 같은 모양으로 맞춘다.
   ★ 이미 들어 있으면 건드리지 않는다 - 두 번 적용해도 안전해야 한다. */
UPDATE meta.load_target
   SET ops  = 'base,ext,exar',
       note = N'경기 안양 (2026-10-20 exar 추가 — 서울과 같은 범위로 맞춤)'
 WHERE sgg_cd IN ('41171','41173')
   AND enabled = 1
   AND ',' + REPLACE(ops, ' ', '') + ',' NOT LIKE '%,exar,%';
PRINT '  안양 행에 exar 추가 (바뀐 행 수는 아래 결과로 확인)';
GO

PRINT '--- 바꾼 뒤: 안양 ---';
SELECT target_id, sgg_cd, bjdong_cd, ops, enabled, note
  FROM meta.load_target WHERE sgg_cd IN ('41171','41173') ORDER BY target_id;
GO

/* ★ 참고용(바꾸지 않는다): exar 가 아직 안 켜진 다른 행이 있나.
   재 보니 'base,ext' 인 행이 셋이었다 - 안양 둘 말고 하나가 더 있다.
   그게 무엇인지 사용자에게 보고하고, 켤지는 묻는다. */
PRINT '--- exar 가 안 켜진 나머지 행 (참고, 변경 안 함) ---';
SELECT target_id, sgg_cd, bjdong_cd, ops, enabled, note
  FROM meta.load_target
 WHERE enabled = 1
   AND ',' + REPLACE(ops, ' ', '') + ',' NOT LIKE '%,exar,%'
 ORDER BY sgg_cd, bjdong_cd;
GO

/* 계획에 실제로 풀렸는지 확인 — 여기서 exar 가 보여야 한다. */
PRINT '--- 확인: 안양 계획의 단계별 법정동 수 ---';
SELECT op_alias, 안양법정동 = COUNT(*),
       TODO = SUM(CASE WHEN 상태 = 'TODO' THEN 1 ELSE 0 END),
       DONE = SUM(CASE WHEN 상태 = 'DONE' THEN 1 ELSE 0 END)
  FROM meta.v_load_plan
 WHERE sgg_cd IN ('41171','41173')
 GROUP BY op_alias ORDER BY op_alias;
GO
