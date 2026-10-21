/* 272. 접속 기록에 요청번호 · 오류 원문 칸 (2026-10-21, 사장님 승인 15:05 — 오류 카드)
   ★ 왜: 화면의 오류 카드가 '오류번호' 를 보여준다. 사용자가 그 번호를 알려 주면
     이 표에서 **그 요청 한 줄**(시각·경로·IP·상태·걸린 시간·원인)이 바로 나와야 한다.
     단지코드만으로는 언제 어느 요청이 실패했는지 모른다(상세·외곽선·공시가격이 따로 나간다).
   ★ 오류 원문은 **여기에만** 적는다. 밖으로는 안 나간다(fail() 은 밖에 한 줄만 준다).
   ★ NULL 칸 추가라 메타데이터만 바뀐다 — 적재·쓰기를 막지 않는다. 다시 돌려도 된다. */
IF COL_LENGTH('ops.req_log', N'요청번호') IS NULL
    ALTER TABLE ops.req_log ADD 요청번호 VARCHAR(12) NULL;
GO
IF COL_LENGTH('ops.req_log', N'오류') IS NULL
    ALTER TABLE ops.req_log ADD 오류 NVARCHAR(400) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_req_log_reqid')
    CREATE INDEX ix_req_log_reqid ON ops.req_log (요청번호) WHERE 요청번호 IS NOT NULL;
GO
SELECT 칸 = name, 형 = TYPE_NAME(system_type_id), 길이 = max_length
  FROM sys.columns WHERE object_id = OBJECT_ID('ops.req_log') AND name IN (N'요청번호', N'오류');
