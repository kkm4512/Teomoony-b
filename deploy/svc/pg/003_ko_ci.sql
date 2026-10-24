-- 10-25: 이름 정렬 콜레이션 — 대소문자만 다른 이름은 '같음'(적재DB Korean_Wansung_CI_AS 처럼) → 다음 정렬 칸으로 넘어가게 nondeterministic.
-- (deterministic 이면 같은 수준에서 코드값으로 다시 갈라 MSSQL 과 순서가 달라진다)
DROP COLLATION IF EXISTS svc.ko_ci;
CREATE COLLATION svc.ko_ci (provider = icu, locale = 'ko-KR-u-ks-level2', deterministic = false);
