-- 서비스DB(PostgreSQL) 001 — 발행 기록 · 단지별 응답 묶음 (2026-10-24 23:30, design.md)
-- ★ 1단계: 단지 하나로 결과가 정해지는 응답(상세 · 지도 경계 · 역사 · 용도 · 주변 몇 칸)은 **지금 서버가 만드는 JSON 을 그대로** 담는다(gzip).
--   결과가 같다는 게 처음부터 보장되고(대조가 쉽다), 화면 코드를 바꾸지 않는다. 검색 · 지도 범위 조회는 2단계(PG 쿼리).
CREATE SCHEMA IF NOT EXISTS svc;
CREATE SCHEMA IF NOT EXISTS app;

CREATE TABLE IF NOT EXISTS svc.publish (
  publish_id  bigserial PRIMARY KEY,
  kind        text        NOT NULL,              -- full · hourly · retry …
  started_at  timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  status      text        NOT NULL DEFAULT 'running',   -- running · ok · failed
  rows_new    int DEFAULT 0, rows_changed int DEFAULT 0, rows_same int DEFAULT 0, rows_failed int DEFAULT 0,
  watermark   timestamptz,                       -- 적재DB 기준선(이 시각까지 끝난 적재분)
  note        text
);

CREATE TABLE IF NOT EXISTS svc.complex_json (
  complex_id  int         NOT NULL,
  kind        text        NOT NULL,              -- detail · geo · buildings · history · usage · landuse · landuse-shape · childcare · pharmacy · hira · closed
  status      smallint    NOT NULL DEFAULT 200,  -- 원 서버의 응답 코드(404 도 그대로 담는다)
  body_gz     bytea       NOT NULL,
  sha         char(64)    NOT NULL,              -- 원문 JSON 의 sha256 — 같으면 안 바꾼다
  bytes       int         NOT NULL,
  publish_id  bigint      NOT NULL,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (complex_id, kind)
);
CREATE INDEX IF NOT EXISTS ix_complex_json_pub ON svc.complex_json (publish_id);

-- 단지 목록(발행 대상 · 우선순위) — 적재DB gold.complex 에서 옮긴다
CREATE TABLE IF NOT EXISTS svc.complex_list (
  complex_id  int PRIMARY KEY,
  hhld        int,
  sgg_cd      char(5),
  merged_into int,
  updated_at  timestamptz NOT NULL DEFAULT now()
);

-- 캐시 적중 기록(Redis · 서버) — 1분마다 서버가 쌓는다
CREATE TABLE IF NOT EXISTS app.cache_stat (
  at   timestamptz NOT NULL,
  kind text        NOT NULL,
  hit  int NOT NULL, miss int NOT NULL, fallback int NOT NULL DEFAULT 0, miss_ms_avg int,
  PRIMARY KEY (at, kind)
);
