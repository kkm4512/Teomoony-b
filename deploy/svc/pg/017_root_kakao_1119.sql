-- 2026-11-19 사장님 "카카오 ㄱㄱ": 사장님 카카오 계정(user_id 5 · 카카오-327f691384 · 11-11 가입)에 관리자(root) 권한.
--   그때까지 root 는 아이디 계정 'root'(아이디 로그인은 11-14 닫힘) · 네이버 계정 1개(user_id 그대로 · 별명은 11-14 시험 때 'QA시험' 으로 바뀜)뿐이라 카카오로 들어오면 관리 화면이 안 보였다.
--   사람 구분은 sub 로(kkmlab 인증 구조 4-3) — sso_link 의 kakao sub 에 붙은 회원만 바꾼다. 로그인 · 세션 구조는 그대로.
--   되돌리기: UPDATE app.app_user SET role = 'user' WHERE user_id = 5;
UPDATE app.app_user u SET role = 'root'
 WHERE u.user_id = 5 AND u.role = 'user'
   AND EXISTS (SELECT 1 FROM app.sso_link l WHERE l.user_id = u.user_id AND l."제공자" = 'kakao');
