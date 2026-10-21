SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* ============================================================
   04_appuser : 적재/조회 전용 최소권한 계정

   sa 를 쓰지 않기 위한 것입니다.
   이 계정은 Teomoony DB 안에서만 읽기/쓰기 + 프로시저 실행이 되고,
   서버 수준 권한(다른 DB, 설정 변경, 계정 생성)은 전혀 없습니다.

   ★ 아래 비밀번호를 바꿔서 쓰세요.
     그리고 같은 값을 C:\Project\Teomoony\etl\config.json 의
     db.password 에 넣으면 됩니다. (채팅에 적지 마세요)
   ============================================================ */
USE master;
GO

DECLARE @pw NVARCHAR(200) = N'CHANGE_ME_please_1234!';   -- <<<< 여기만 바꾸세요

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'teomoony_app')
BEGIN
    EXEC('CREATE LOGIN teomoony_app WITH PASSWORD = ' + QUOTENAME(@pw, '''')
         + ', DEFAULT_DATABASE = Teomoony, CHECK_POLICY = ON');
    PRINT 'login teomoony_app created.';
END
ELSE
BEGIN
    EXEC('ALTER LOGIN teomoony_app WITH PASSWORD = ' + QUOTENAME(@pw, ''''));
    PRINT 'login teomoony_app password updated.';
END
GO

USE Teomoony;
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'teomoony_app')
BEGIN
    CREATE USER teomoony_app FOR LOGIN teomoony_app;
    PRINT 'db user created.';
END
GO

/* 읽기/쓰기만. db_owner 는 주지 않는다 */
ALTER ROLE db_datareader ADD MEMBER teomoony_app;
ALTER ROLE db_datawriter ADD MEMBER teomoony_app;
GO

/* 프로시저/함수 실행 권한 (단지 구성, PNU 조립) */
GRANT EXECUTE ON SCHEMA::gold   TO teomoony_app;
GRANT EXECUTE ON SCHEMA::meta   TO teomoony_app;
GRANT EXECUTE ON SCHEMA::silver TO teomoony_app;
GO

/* IDENTITY 컬럼이 있는 테이블에 직접 INSERT 할 때 필요할 수 있음 */
GRANT INSERT, UPDATE, SELECT ON SCHEMA::bronze TO teomoony_app;
GRANT INSERT, UPDATE, SELECT ON SCHEMA::silver TO teomoony_app;
GRANT INSERT, UPDATE, SELECT, DELETE ON SCHEMA::gold TO teomoony_app;
GRANT INSERT, UPDATE, SELECT ON SCHEMA::meta TO teomoony_app;
GO

/* 명시적으로 막아두는 것들 */
DENY ALTER ANY SCHEMA, CREATE TABLE, CREATE PROCEDURE, CREATE VIEW TO teomoony_app;
GO

PRINT '04_appuser done.  login=teomoony_app';
GO
