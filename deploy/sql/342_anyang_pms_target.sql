/* 2026-10-24 전국 넓히기 전 — 범위표가 보여 준 구멍: 안양(41171 · 41173)은 건축인허가(pms)를 목표에 안 넣어 두었다(서울 먼저 · 11-235 보류).
   목표 설정(meta.load_target)에 pms · pmsdong 을 더한다. 받는 일은 run_plan go --grp pms 가 한다. */
UPDATE meta.load_target
   SET ops = ops + ',pms'
 WHERE sgg_cd IN ('41171', '41173') AND enabled = 1 AND bjdong_cd IS NULL AND ',' + ops + ',' NOT LIKE '%,pms,%';
SELECT j = (SELECT sgg_cd, ops FROM meta.load_target WHERE sgg_cd IN ('41171', '41173') FOR JSON PATH);
