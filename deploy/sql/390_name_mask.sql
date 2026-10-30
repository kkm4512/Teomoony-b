/* 390 개인 이름 가리기 — 건물 이름 끝 괄호의 사람 이름 (2026-10-30 프론트 QA · 사장님 "ㄱㄱ")
   ★ 왜: 건축물대장 원문 건물명에 소유자 이름이 괄호로 붙어 있다 — "위례 택지개발지구 D2-4 9-5 단독주택 (홍길동)".
     검색 제안 · 지도 · 상세 제목에 그대로 나갔다(괄호 끝이 한글 이름 꼴인 단지 2만여 곳). 대표자 이름을 안 보이는 원칙과 같은 까닭으로 가린다.
   ★ 원문은 그대로다(silver · hub 의 건물명은 안 건드린다). 가리는 곳은 **화면에 나가는 이름**만:
     gold.complex.complex_nm(파생 — 단지 이름) · gold.closed_site.이름(파생 — 옛 대장 이름) · 파생표 pre_build · house_plan 이름 · 서버가 내보내는 허가 건물명.
   ★ 규칙(짐작이 섞인다 — 그래서 좁게): 이름 **끝** 괄호 안이
       · 한글 3글자 · 첫 글자가 흔한 성씨 · 끝 글자가 지명 · 시설 말(군 시 구 동 읍 면 리 관 점 사 소 장 당 터 집 식 층 창 청 국 처 과 팀 회 업 대 촌 역 교 도 산 천 강 실)이 아님
       · 또는 한글 4글자 · 앞 두 글자가 두 글자 성(남궁 황보 제갈 선우 독고 사공 서문)
       · 뒤에 ' 외 1' · '외2인' 같은 꼬리가 있으면 떼고 본다
     → 그 괄호를 '(개인 이름 가림)' 으로 바꾼다. 지명(신안군) · 동 이름(가동) · 시설(창고 · 경로당)은 그대로 둔다.
     · 사람 이름 꼴인 기관 · 지명(유치원 · 국방부 · 이태원 …)은 낱말로 뺀다(첫 실행 44,452곳 중 괄호 말 상위를 눈으로 본 결과).
   ★ 10-30 23:10 덧붙임: 괄호 안 **'대표 · 대표자 · 대표이사' 뒤의 사람 이름**도 가린다 — "(유진건설(주)대표김승일)" · "((주)도솔대표:이정국)".
     단지 388 · 허가 9,957 · 옛 대장 61 에 나가고 있었다(첫 규칙은 괄호 안이 이름뿐일 때만 봤다). 대표 뒤는 2~4글자 · 성씨로 시작하면 이름으로 본다.
     대표 뒤가 3~4글자(띄움표 ':' 뒤면 2글자도) · 성씨로 시작하면 이름으로 본다('대표단지' 같은 붙은 2글자는 아님). 괄호 안에 괄호가 있으면("(유한회사로젠목포(대표:장형권))") 끝 ')' 의 짝 '(' 부터 본다.
   ★ 새로 만들어지는 이름도 가려지게 두 표에 트리거(gold.complex · gold.closed_site — 둘 다 제자리 갱신 표). */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* 다시 돌릴 때: fn_name_mask 가 fn_is_person_name 에 묶여 있으면(SCHEMABINDING) 고칠 수 없다 — 잠깐 묶음을 푼다(바로 아래에서 다시 만든다) */
IF OBJECT_ID('gold.fn_name_mask') IS NOT NULL
    EXEC (N'CREATE OR ALTER FUNCTION gold.fn_name_mask (@s NVARCHAR(400)) RETURNS NVARCHAR(400) AS BEGIN RETURN @s END');
GO
CREATE OR ALTER FUNCTION gold.fn_is_person_name (@in NVARCHAR(400)) RETURNS BIT WITH SCHEMABINDING AS
BEGIN
    DECLARE @s NVARCHAR(400) = LTRIM(RTRIM(ISNULL(@in, N'')));
    /* 10-30 23:10 '…대표 이름' · '대표자 · 대표이사' — 대표 뒤만 본다(대표 앞의 회사 이름까지 같이 가린다) */
    DECLARE @r INT = CHARINDEX(N'표대', REVERSE(@s));
    IF @r > 0
    BEGIN
        DECLARE @n NVARCHAR(400) = RIGHT(@s, @r - 1);
        IF @n LIKE N'이사%' SET @n = SUBSTRING(@n, 3, 50);
        IF @n LIKE N'자%' SET @n = SUBSTRING(@n, 2, 50);
        DECLARE @띔 BIT = CASE WHEN @n LIKE N'[:;： ./]%' THEN 1 ELSE 0 END;
        IF CHARINDEX(N',', @n) > 0 SET @n = LEFT(@n, CHARINDEX(N',', @n) - 1);   -- '대표:윤우석,윤성수' — 첫 이름으로 본다   -- '대표:홍길' 처럼 띄운 2글자만 이름으로(붙은 '대표단지' 는 아님)
        SET @n = LTRIM(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(@n, N':', N''), N';', N''), N'：', N''), N' ', N''), N')', N''), N'(', N''));
        SET @n = REPLACE(REPLACE(REPLACE(REPLACE(@n, N'.', N''), N'/', N''), N'[', N''), N']', N'');
        DECLARE @w2 INT = CHARINDEX(N'외', @n);
        IF @w2 > 2 AND SUBSTRING(@n, @w2 + 1, 10) NOT LIKE N'%[^0-9 인명]%' SET @n = LEFT(@n, @w2 - 1);
        IF @n NOT LIKE N'%[^가-힣]%' AND (LEN(@n) IN (3, 4) OR (LEN(@n) = 2 AND @띔 = 1))
           AND (CHARINDEX(LEFT(@n, 1), N'김이박최정강조윤장임한오서신권황안송류유전홍고문양손배백허남심노하곽성차주우구민나진지엄채원천방공현함변염여추도소석선설마길연위표명기반왕금옥육인맹제모탁국어은편용예봉경사부가복태목형계피두감음빈동온호범좌팽승간상시갈단견당화창옹순빙종풍') > 0
                OR LEFT(@n, 2) IN (N'남궁', N'황보', N'제갈', N'선우', N'독고', N'사공', N'서문'))
            RETURN 1;
        RETURN 0;
    END
    /* ' 외 1' · '외2인' · '외 3명' 꼬리 떼기 */
    DECLARE @w INT = CHARINDEX(N'외', @s);
    IF @w > 3 AND SUBSTRING(@s, @w + 1, 10) NOT LIKE N'%[^0-9 인명]%' SET @s = RTRIM(LEFT(@s, @w - 1));
    IF @s LIKE N'%[^가-힣]%' RETURN 0;
    /* 사람 이름 꼴이지만 기관 · 시설 · 지명인 말(첫 실행 검토에서 나온 것) */
    IF @s IN (N'유치원', N'국방부', N'이태원', N'한의원', N'요양원', N'보육원', N'양로원', N'수녀원', N'고아원', N'연구원', N'교육원', N'수련원',
              N'신학원', N'수도원', N'기도원', N'시법원', N'이의원', N'신라원') RETURN 0;
    IF LEN(@s) = 3
       AND CHARINDEX(LEFT(@s, 1), N'김이박최정강조윤장임한오서신권황안송류유전홍고문양손배백허남심노하곽성차주우구민나진지엄채원천방공현함변염여추도소석선설마길연위표명기반왕금옥육인맹제모탁국어은편용예봉경사부가복태목형계피두감음빈동온호범좌팽승간상시갈단견당화창옹순빙종풍') > 0
       AND CHARINDEX(RIGHT(@s, 1), N'군시구동읍면리관점사소장당터집식층창청국처과팀회업대촌역교도산천강실') = 0
        RETURN 1;
    IF LEN(@s) = 4 AND LEFT(@s, 2) IN (N'남궁', N'황보', N'제갈', N'선우', N'독고', N'사공', N'서문') RETURN 1;
    RETURN 0;
END
GO
CREATE OR ALTER FUNCTION gold.fn_name_mask (@s NVARCHAR(400)) RETURNS NVARCHAR(400) AS
BEGIN
    IF @s IS NULL RETURN NULL;
    DECLARE @t NVARCHAR(400) = RTRIM(@s);
    IF RIGHT(@t, 1) <> N')' OR CHARINDEX(N'(', @t) = 0 RETURN @s;
    /* 끝 ')' 의 짝 '(' — 괄호 안 괄호("(유한회사로젠목포(대표:장형권))")까지 센다 */
    DECLARE @p INT = LEN(@t), @d INT = 0;
    WHILE @p > 0
    BEGIN
        IF SUBSTRING(@t, @p, 1) = N')' SET @d += 1;
        ELSE IF SUBSTRING(@t, @p, 1) = N'(' BEGIN SET @d -= 1; IF @d = 0 BREAK; END
        SET @p -= 1;
    END
    IF @p < 1 SET @p = LEN(@t) - CHARINDEX(N'(', REVERSE(@t)) + 1;   -- 짝이 안 맞는 괄호('(주)서평건설대표이광기)')는 마지막 '(' 부터
    IF gold.fn_is_person_name(SUBSTRING(@t, @p + 1, LEN(@t) - @p - 1)) = 0 RETURN @s;
    RETURN RTRIM(LEFT(@t, @p - 1)) + N' (개인 이름 가림)';
END
GO
/* 가린 단지 기록(번호와 때만 — 원래 이름은 적지 않는다) · 서비스DB 의 옛 응답을 지우는 데 쓴다 */
IF OBJECT_ID('ops.name_mask_log') IS NULL
CREATE TABLE ops.name_mask_log (종류 VARCHAR(20) NOT NULL, 키 VARCHAR(80) NOT NULL, 때 DATETIME2(0) NOT NULL CONSTRAINT df_name_mask_log DEFAULT SYSDATETIME());
GO
CREATE OR ALTER TRIGGER gold.tr_complex_name_mask ON gold.complex AFTER INSERT, UPDATE AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(complex_nm) RETURN;
    UPDATE c SET complex_nm = gold.fn_name_mask(i.complex_nm)
      OUTPUT 'complex', CAST(inserted.complex_id AS VARCHAR(80)) INTO ops.name_mask_log (종류, 키)
      FROM gold.complex c JOIN inserted i ON i.complex_id = c.complex_id
     WHERE i.complex_nm LIKE N'%)' AND gold.fn_name_mask(i.complex_nm) <> i.complex_nm;
END
GO
CREATE OR ALTER TRIGGER gold.tr_closed_site_name_mask ON gold.closed_site AFTER INSERT, UPDATE AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(이름) RETURN;
    UPDATE c SET 이름 = gold.fn_name_mask(i.이름)
      OUTPUT 'closed_site', CAST(inserted.site_key AS VARCHAR(80)) INTO ops.name_mask_log (종류, 키)
      FROM gold.closed_site c JOIN inserted i ON i.site_key = c.site_key
     WHERE i.이름 LIKE N'%)' AND gold.fn_name_mask(i.이름) <> i.이름;
END
GO
/* 지금 있는 것 — 한 번(트리거가 받아 가린다: 같은 값으로 다시 쓰면 UPDATE(complex_nm) 이 서고 트리거가 가린다) */
UPDATE gold.complex SET complex_nm = complex_nm WHERE complex_nm LIKE N'%)' AND gold.fn_name_mask(complex_nm) <> complex_nm;
SELECT 단지 = @@ROWCOUNT;
UPDATE gold.closed_site SET 이름 = 이름 WHERE 이름 LIKE N'%)' AND gold.fn_name_mask(이름) <> 이름;
SELECT 옛대장 = @@ROWCOUNT;
IF OBJECT_ID('gold.pre_build') IS NOT NULL UPDATE gold.pre_build SET 이름 = gold.fn_name_mask(이름) WHERE 이름 LIKE N'%)' AND gold.fn_name_mask(이름) <> 이름;
IF OBJECT_ID('gold.house_plan') IS NOT NULL UPDATE gold.house_plan SET 이름 = gold.fn_name_mask(이름) WHERE 이름 LIKE N'%)' AND gold.fn_name_mask(이름) <> 이름;
IF OBJECT_ID('gold.pre_complex') IS NOT NULL UPDATE gold.pre_complex SET 이름 = gold.fn_name_mask(이름) WHERE 이름 LIKE N'%)' AND gold.fn_name_mask(이름) <> 이름;
GO
SELECT 기록 = (SELECT STRING_AGG(CONCAT(종류, ':', n), ', ') FROM (SELECT 종류, n = COUNT(*) FROM ops.name_mask_log GROUP BY 종류) z),
       예 = (SELECT TOP 1 complex_nm FROM gold.complex WHERE complex_nm LIKE N'%(개인 이름 가림)' ORDER BY complex_id),
       안가린예 = (SELECT STRING_AGG(complex_nm, ' | ') FROM (SELECT TOP 6 complex_nm FROM gold.complex WHERE complex_nm LIKE N'%(신안군)' OR complex_nm LIKE N'%(가동)' OR complex_nm LIKE N'%(창고)' OR complex_nm LIKE N'%(경로당)') z);
GO
/* 낱말로 뺀 것(유치원 · 국방부 …)을 첫 실행에서 가렸으면 원문 괄호로 되돌린다 — 원문(총괄표제부 · 표제부 건물명)의 끝 괄호 말 그대로 */
UPDATE c SET complex_nm = LEFT(c.complex_nm, LEN(c.complex_nm) - LEN(N' (개인 이름 가림)')) + CASE WHEN o.앞빈칸 = 1 THEN N' ' ELSE N'' END + N'(' + o.안 + N')'
  FROM gold.complex c
  CROSS APPLY (SELECT nm = RTRIM(COALESCE(NULLIF(r.bld_nm, ''), NULLIF(t.bld_nm, '')))
                 FROM (SELECT 1 x) d
                 LEFT JOIN silver.bld_recap_title r ON r.mgm_bldrgst_pk = c.root_bldrgst_pk AND r.is_current = 1
                 LEFT JOIN silver.bld_title t ON t.mgm_bldrgst_pk = c.root_bldrgst_pk AND t.is_current = 1) s
  CROSS APPLY (SELECT 안 = SUBSTRING(s.nm, LEN(s.nm) - CHARINDEX('(', REVERSE(s.nm)) + 2, CHARINDEX('(', REVERSE(s.nm)) - 2),
                      앞빈칸 = CASE WHEN SUBSTRING(s.nm, LEN(s.nm) - CHARINDEX('(', REVERSE(s.nm)), 1) = ' ' THEN 1 ELSE 0 END) o
 WHERE c.complex_nm LIKE N'%(개인 이름 가림)' AND s.nm LIKE N'%)' AND gold.fn_is_person_name(o.안) = 0;
SELECT 되돌림 = @@ROWCOUNT;

