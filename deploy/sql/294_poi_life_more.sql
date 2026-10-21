/* 294 : 생활 편의 묶음을 넓힌다 — 병원을 과목으로 쪼개고, PC방·노래방·독서실·목욕탕 등을 더한다 (2026-10-21, 사장님 "1번 ㄱㄱ")
   ★ 새 자료는 없다. 이미 받은 소상공인 상가정보(silver.semas_store)의 **소분류 이름 그대로** 묶는다.
   ★ 병원·의원(Q1 통째)을 쪼갠 까닭: 치과·피부과·성형외과까지 '병원 37곳' 으로 세면 아이 아플 때 갈 곳이 몇 곳인지 모른다.
       내과·소아과  = '내과/소아과 의원' — 원본이 **한 칸**이라 소아과만 셀 수는 없다(이름에 그대로 적는다)
       치과         = 치과의원 + 치과병원        한의원 = 한의원 + 한방병원
       병원·종합병원 = 일반병원 + 종합병원        요양병원 = 요양병원
       그 외 의원   = Q102 의원의 나머지(피부·외과·이비인후과·안과·산부인과 …)
     Q104 '기타 보건/유사 의료업'(699) 은 **병원이 아니라서** 묶음에서 뺀다(소분류 막대에는 남는다).
   ★ 더한 것: 동물병원 · 독서실·스터디카페 · 수영장 · 골프연습장 · 목욕탕·사우나 · PC방 · 노래방 · 당구장·볼링장.
   ★ 뷰 정의는 DB 에 있는 것 그대로 꺼내 두 자리만 바꾼다(292 와 같은 방식). 자리가 정확히 하나씩일 때만. */
SET NOCOUNT ON;
DECLARE @d NVARCHAR(MAX), @a NVARCHAR(400), @b NVARCHAR(400), @na INT, @nb INT, @nl NCHAR(2) = NCHAR(13) + NCHAR(10);
SET @d = OBJECT_DEFINITION(OBJECT_ID('gold.v_complex_poi'));
SET @a = N'WHEN s.inds_lcls_cd = ''Q1''        THEN N''병원·의원''';
SET @b = N'WHEN s.inds_scls_nm = N''세탁소''   THEN N''세탁소''';
SET @na = (LEN(@d) - LEN(REPLACE(@d, @a, N''))) / LEN(@a);
SET @nb = (LEN(@d) - LEN(REPLACE(@d, @b, N''))) / LEN(@b);
IF @na = 1 AND @nb = 1 AND @d NOT LIKE N'%내과·소아과%'
BEGIN
    SET @d = REPLACE(@d, @a,
                 N'/* 294 — 병원을 과목으로 쪼갠다. Q104 유사 의료업은 병원이 아니라 뺀다 */' + @nl
      + N'           WHEN s.inds_scls_nm = N''내과/소아과 의원''         THEN N''내과·소아과''' + @nl
      + N'           WHEN s.inds_scls_nm IN (N''치과의원'', N''치과병원'') THEN N''치과''' + @nl
      + N'           WHEN s.inds_scls_nm IN (N''한의원'', N''한방병원'')   THEN N''한의원''' + @nl
      + N'           WHEN s.inds_scls_nm IN (N''일반병원'', N''종합병원'') THEN N''병원·종합병원''' + @nl
      + N'           WHEN s.inds_scls_nm = N''요양병원''                 THEN N''요양병원''' + @nl
      + N'           WHEN s.inds_mcls_cd = ''Q102''                      THEN N''그 외 의원''' + @nl
      + N'           WHEN s.inds_scls_nm = N''동물병원''                 THEN N''동물병원''');
    SET @d = REPLACE(@d, @b, @b + @nl
      + N'           /* 294 — 공부·운동·놀거리 */' + @nl
      + N'           WHEN s.inds_scls_nm = N''독서실/스터디 카페''       THEN N''독서실·스터디카페''' + @nl
      + N'           WHEN s.inds_scls_nm = N''수영장''                   THEN N''수영장''' + @nl
      + N'           WHEN s.inds_scls_nm = N''골프 연습장''              THEN N''골프연습장''' + @nl
      + N'           WHEN s.inds_scls_nm = N''목욕탕/사우나''            THEN N''목욕탕·사우나''' + @nl
      + N'           WHEN s.inds_scls_nm = N''PC방''                     THEN N''PC방''' + @nl
      + N'           WHEN s.inds_scls_nm = N''노래방''                   THEN N''노래방''' + @nl
      + N'           WHEN s.inds_scls_nm IN (N''당구장'', N''볼링장'')     THEN N''당구장·볼링장''');
    SET @d = STUFF(@d, CHARINDEX(N'CREATE VIEW', @d), LEN(N'CREATE VIEW'), N'CREATE OR ALTER VIEW');
    EXEC sp_executesql @d;
END
SELECT 자리a = @na, 자리b = @nb,
       바뀜 = CASE WHEN OBJECT_DEFINITION(OBJECT_ID('gold.v_complex_poi')) LIKE N'%내과·소아과%' THEN 1 ELSE 0 END;
GO
SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT j = (SELECT 항목 = life, n = COUNT(*), r500 = SUM(CASE WHEN dist_m <= 500 THEN 1 ELSE 0 END)
              FROM gold.v_complex_poi WHERE complex_id = 48857 AND life IS NOT NULL GROUP BY life FOR JSON PATH);
