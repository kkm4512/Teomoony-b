/* ============================================================
   315_usage_split : 이용현황을 사람 · 로봇으로 가르고, 운영자(사장님) 접속은 뺀다 (2026-10-22 사장님
   "권장으로 가고, 내 IP 는 이용현황에서 제외 · 이미 적재됐으면 DELETE 해도 좋아")
   ★ ops.usage_hour 에 갈래(사람 · 검색 로봇 · AI 수집 로봇 · …)를 더한다. 공개 화면은 **갈래별 수와 나라만** — IP 는 안 보인다.
   ★ 운영자 IP = **root 로 로그인한 요청이 들어온 IP**(계정이 root 하나뿐이라 그게 사장님이다). 서버가 그때마다 이 표에 더한다.
     지금 셋은 기록(req_log)의 root 로그인 · 내 정보 · AI 검색 성공 요청에서 찾았다.
   ★ 지난 수치는 서버의 /api/_usage_rebuild 가 req_log 로 다시 센다(사장님 허락 — 그 시간대 usage_hour 를 지우고 다시 넣는다).
     req_log 의 운영자 줄은 **지우지 않는다**(오류를 거슬러 찾을 때 쓴다 — 문의 #2) — 이용현황에서만 뺀다.
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
IF OBJECT_ID('ops.usage_owner_ip') IS NULL
CREATE TABLE ops.usage_owner_ip (
    ip     VARCHAR(45)   NOT NULL CONSTRAINT pk_usage_owner_ip PRIMARY KEY,
    처음   DATETIME2(0)  NOT NULL CONSTRAINT df_owner_ip_t DEFAULT SYSDATETIME(),
    근거   NVARCHAR(100) NULL
);
GO
INSERT INTO ops.usage_owner_ip (ip, 근거)
SELECT v.ip, N'root 로그인 요청(req_log, 2026-10-22 확인)' FROM (VALUES
  ('1.233.87.162'), ('2406:5900:10fc:9b4:b96e:e7c3:dfb8:8503'), ('2001:4430:502f:f314:384b:4f6b:1b5e:8886')) v(ip)
 WHERE NOT EXISTS (SELECT 1 FROM ops.usage_owner_ip o WHERE o.ip = v.ip);
GO
IF COL_LENGTH('ops.usage_hour', '갈래') IS NULL
    ALTER TABLE ops.usage_hour ADD 갈래 NVARCHAR(20) NOT NULL CONSTRAINT df_usage_hour_kind DEFAULT N'모름';
GO
IF EXISTS (SELECT 1 FROM sys.index_columns ic JOIN sys.indexes i ON i.object_id = ic.object_id AND i.index_id = ic.index_id
            WHERE i.name = 'pk_usage_hour' AND i.object_id = OBJECT_ID('ops.usage_hour')
           HAVING COUNT(*) = 2)
BEGIN
    ALTER TABLE ops.usage_hour DROP CONSTRAINT pk_usage_hour;
    ALTER TABLE ops.usage_hour ADD CONSTRAINT pk_usage_hour PRIMARY KEY CLUSTERED (시각, 동작, 갈래);
END
GO
SELECT 운영자IP = (SELECT COUNT(*) FROM ops.usage_owner_ip),
       키 = (SELECT STRING_AGG(c.name, ',') FROM sys.index_columns ic JOIN sys.indexes i ON i.object_id = ic.object_id AND i.index_id = ic.index_id
                JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
              WHERE i.name = 'pk_usage_hour' AND i.object_id = OBJECT_ID('ops.usage_hour'));
