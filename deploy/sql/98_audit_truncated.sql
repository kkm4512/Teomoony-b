SET NOCOUNT ON;
/* ============================================================
   98_audit_truncated — OK 로 적혔지만 실제로는 잘린 적재 — 2026-10-17

   Ctrl+C 로 끊긴 적재가 status=OK 로 남았다(판정이 try 안에 있어 중단 시
   건너뛰었다). run_plan 은 OK 를 DONE 으로 보고 영영 안 채운다.

   ★ 본문 전체를 뒤지지 않는다.
     data.go.kr XML 은 <totalCount> 가 **맨 뒤**에 있다:
       <response><header/><body><items>...</items>
         <numOfRows/><pageNo/><totalCount>9174</totalCount></body></response>
     그래서 RIGHT(body, 300) 만 본다. 응답 하나가 85KB 라 이 차이가 크다.
     (처음에 CHARINDEX 를 본문 전체에 걸었다가 몇 분씩 걸렸다)

   ★ run 당 응답 하나만 읽는다. 한 run 안에서는 totalCount 가 같다.

   판정: req_count * 100 < totalCount  -> 끝까지 안 돌았다.
         마지막 페이지가 100 미만일 수 있어 **보수적**이다.
         걸리면 확실히 모자라고, 안 걸려도 온전하다고 단정하진 않는다.
   ============================================================ */
WITH one AS (
    SELECT p.run_id, pid = MIN(p.payload_id)
      FROM bronze.api_payload p
      JOIN meta.ingest_run r ON r.run_id = p.run_id
     WHERE r.status = 'OK'
     GROUP BY p.run_id
),
t AS (
    SELECT o.run_id, tail = RIGHT(p.body, 300)
      FROM one o JOIN bronze.api_payload p ON p.payload_id = o.pid
),
x AS (
    SELECT run_id,
           totalCount = TRY_CONVERT(INT,
               CASE WHEN CHARINDEX('<totalCount>', tail) > 0
                    THEN SUBSTRING(tail,
                           CHARINDEX('<totalCount>', tail) + 12,
                           CHARINDEX('</totalCount>', tail)
                           - CHARINDEX('<totalCount>', tail) - 12)
               END)
      FROM t
)
SELECT s.operation, r.scope_key,
       호출 = r.req_count, 적재행 = r.row_count,
       totalCount = x.totalCount,
       최대수신 = r.req_count * 100,
       모자람 = x.totalCount - r.req_count * 100,
       r.started_at
  FROM meta.ingest_run r
  JOIN meta.api_source s ON s.source_id = r.source_id
  JOIN x ON x.run_id = r.run_id
 WHERE x.totalCount IS NOT NULL
   AND r.req_count * 100 < x.totalCount
 ORDER BY (x.totalCount - r.req_count * 100) DESC;
