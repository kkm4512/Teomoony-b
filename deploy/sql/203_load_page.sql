/* =====================================================================
   meta.load_page — 받은 **페이지**를 적는다 (2026-10-19)

   ★ 왜 필요한가
     지금 이어받기는 **행 수로 역산**한다:
         "DB 255,200행 -> --from-page 2550"
     이건 "받은 행 수가 곧 앞에서부터 연속된 페이지" 라는 **가정**이다.
     적재기 주석도 그렇게 적어 뒀다 — "앞 페이지가 꽉 찼다는 가정이므로
     추정치임을 밝힌다 / 그 구간이 실제로 들어와 있는지는 확인하고 쓰십시오".

     페이지를 **병렬로** 받으면 그 가정이 깨진다. 3페이지가 먼저 들어오고
     2페이지가 실패해도 행 수는 똑같이 는다. 다음 이어받기는 그 구멍을 모르고
     더 뒤로 건너뛴다 — **조용히 빠진 페이지**가 생기고, 화면에서는
     "이 단지는 공시가격이 없네" 로 보인다. 정책 1장: 조용히 틀린 값은
     NULL 보다 나쁘다.

     그래서 추정하지 말고 **받은 페이지를 그대로 적는다.** 그러면
       - 병렬로 받아도 이어받기가 정확하고
       - **어느 페이지가 비었는지 물어볼 수 있다** (이게 진짜 이득이다)

   ★ 키는 (시군구, 법정동, op, 페이지). 같은 페이지를 다시 받으면 덮는다 -
     SCD 업서트가 '동일' 로 떨어지므로 페이지 재실행은 원래 안전하다.
   ===================================================================== */
USE Teomoony;
GO
IF OBJECT_ID('meta.load_page') IS NULL
BEGIN
  CREATE TABLE meta.load_page (
      sgg_cd     CHAR(5)       NOT NULL,
      bjdong_cd  CHAR(5)       NOT NULL,
      op         VARCHAR(40)   NOT NULL,   -- 별칭 (hsprc, expos, ...)
      page       INT           NOT NULL,
      -- 이 페이지가 돌려준 item 수. 100 미만이면 **마지막 페이지**이거나
      -- API 가 끊은 것이다. 0 은 빈 응답(실패로 본다).
      items      INT           NOT NULL,
      status     VARCHAR(10)   NOT NULL,   -- OK / EMPTY / FAIL
      api_total  INT           NULL,       -- 그때 응답의 totalCount
      run_id     BIGINT        NULL,
      fetched_at DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
      CONSTRAINT PK_load_page PRIMARY KEY (sgg_cd, bjdong_cd, op, page)
  );
  PRINT 'meta.load_page 생성';
END
ELSE PRINT 'meta.load_page 이미 있음';
GO

/* 어디까지 받았나 / 어디가 비었나 — 사람이 바로 물어보는 두 가지 */
CREATE OR ALTER VIEW meta.v_load_page_gap
AS
SELECT sgg_cd, bjdong_cd, op,
       받은페이지 = COUNT(*),
       최대페이지 = MAX(page),
       /* 1..최대 중 **빠진 수**. 0 이어야 정상이다. */
       빠진페이지 = MAX(page) - COUNT(*),
       실패 = SUM(CASE WHEN status <> 'OK' THEN 1 ELSE 0 END),
       api_total = MAX(api_total),
       받은건수 = SUM(items)
  FROM meta.load_page
 GROUP BY sgg_cd, bjdong_cd, op;
GO
PRINT '203_load_page 완료';
GO
