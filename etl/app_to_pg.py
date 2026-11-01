#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""app_to_pg - 화면이 쓰는 '앱 상태'(회원 · 문의 · 알림 · 관심 단지 · AI 질문 · 이용현황 · 접속 기록)를 서비스DB(app.*) 로 옮긴다 (2026-11-01, 서비스DB 분리 4묶음)
  py app_to_pg.py            # 처음 옮기기(app.* 가 비어 있을 때만) · 그 뒤로는 접속 기록 · 이용현황만 이어 붙임(넘어가기 전 따라잡기)
  py app_to_pg.py --check    # 양쪽 줄 수만 비교
★ 넘어간 뒤(svc_mode "app": true)에는 app.* 가 원본이다 — 이 스크립트는 app.cutover 가 적혀 있으면 아무것도 덮어쓰지 않는다.
★ 번호(user_id · inquiry_id · notice_id · ask_id · log_sk)는 그대로 옮기고 일련번호를 그 뒤로 맞춘다(알림 → 문의 번호가 이어진다).
★ 때(datetime2)는 적재DB 의 벽시계 값 그대로(SYSDATETIME = UTC · 접속 기록 '때' = 한국시간). 화면은 node-mssql 과 같게 UTC 로 읽는다(src/appdb.js)."""
import argparse, sys, time
from svc_publish import env, ms_conn, pg_conn

DDL = """
CREATE SCHEMA IF NOT EXISTS app;
CREATE TABLE IF NOT EXISTS app.cutover (at timestamptz NOT NULL DEFAULT now(), note text);
CREATE TABLE IF NOT EXISTS app.copy_state (name text PRIMARY KEY, last bigint NOT NULL);
CREATE TABLE IF NOT EXISTS app.app_user (user_id serial PRIMARY KEY, username text NOT NULL UNIQUE, pw_salt text NOT NULL, pw_hash text NOT NULL,
  role text NOT NULL DEFAULT 'user', is_active boolean NOT NULL DEFAULT true, created_at timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'UTC'),
  last_login timestamp, pw_changed timestamp);
CREATE TABLE IF NOT EXISTS app.inquiry (inquiry_id serial PRIMARY KEY, "때" timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'UTC'), user_id int, "아이디" text,
  "종류" text NOT NULL, "무엇" text, "말" text, "오류번호" text, "단지코드" text, "화면" text, "내용" text, "상태" text NOT NULL DEFAULT '새로',
  "답변" text, "답변때" timestamp, "답변자" text);
CREATE INDEX IF NOT EXISTS ix_inquiry_때 ON app.inquiry ("때");
CREATE TABLE IF NOT EXISTS app.notice (notice_id serial PRIMARY KEY, user_id int NOT NULL, "때" timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'UTC'),
  "종류" text NOT NULL, "제목" text NOT NULL, "내용" text, inquiry_id int, "읽은때" timestamp);
CREATE INDEX IF NOT EXISTS ix_notice_user ON app.notice (user_id, "읽은때");
CREATE TABLE IF NOT EXISTS app.fav_complex (user_id int NOT NULL, complex_id int NOT NULL, "넣은때" timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'UTC'),
  "뺀때" timestamp, PRIMARY KEY (user_id, complex_id));
CREATE TABLE IF NOT EXISTS app.ask_log (ask_id bigserial PRIMARY KEY, "때" timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'UTC'), user_id int, "아이디" text,
  "질문" text NOT NULL, "종류" text, "해석" text, "결과수" int);
CREATE INDEX IF NOT EXISTS ix_ask_log_때 ON app.ask_log ("때");
CREATE INDEX IF NOT EXISTS ix_ask_log_user ON app.ask_log (user_id, "때");
CREATE TABLE IF NOT EXISTS app.usage_hour ("시각" timestamp NOT NULL, "동작" text NOT NULL, "횟수" int NOT NULL, "갈래" text NOT NULL DEFAULT '모름',
  PRIMARY KEY ("시각", "동작", "갈래"));
CREATE TABLE IF NOT EXISTS app.usage_owner_ip (ip text PRIMARY KEY, "처음" timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'UTC'), "근거" text);
CREATE TABLE IF NOT EXISTS app.req_log (log_sk bigserial PRIMARY KEY, "때" timestamp NOT NULL, ip text, "내부" boolean NOT NULL DEFAULT false, "경로" text NOT NULL,
  "질의" text, "동작" text, "상태" smallint, "밀리" int, "나라" text, ua text, "리퍼러" text, "요청번호" text, "오류" text);
CREATE INDEX IF NOT EXISTS ix_req_log_때 ON app.req_log ("때");
CREATE INDEX IF NOT EXISTS ix_req_log_ip ON app.req_log (ip, "때");
CREATE INDEX IF NOT EXISTS ix_req_log_reqid ON app.req_log ("요청번호");
"""
# (PG 표, 적재DB 질의, 칸, 일련번호 칸)
SMALL = [
  ("app.app_user", "SELECT user_id, username, pw_salt, pw_hash, role, is_active, created_at, last_login, pw_changed FROM meta.app_user",
   ["user_id", "username", "pw_salt", "pw_hash", "role", "is_active", "created_at", "last_login", "pw_changed"], "user_id"),
  ("app.inquiry", "SELECT inquiry_id, 때, user_id, 아이디, 종류, 무엇, 말, 오류번호, 단지코드, 화면, 내용, 상태, 답변, 답변때, 답변자 FROM ops.inquiry",
   ["inquiry_id", "때", "user_id", "아이디", "종류", "무엇", "말", "오류번호", "단지코드", "화면", "내용", "상태", "답변", "답변때", "답변자"], "inquiry_id"),
  ("app.notice", "SELECT notice_id, user_id, 때, 종류, 제목, 내용, inquiry_id, 읽은때 FROM ops.notice",
   ["notice_id", "user_id", "때", "종류", "제목", "내용", "inquiry_id", "읽은때"], "notice_id"),
  ("app.fav_complex", "SELECT user_id, complex_id, 넣은때, 뺀때 FROM ops.fav_complex", ["user_id", "complex_id", "넣은때", "뺀때"], None),
  ("app.ask_log", "SELECT ask_id, 때, user_id, 아이디, 질문, 종류, 해석, 결과수 FROM ops.ask_log",
   ["ask_id", "때", "user_id", "아이디", "질문", "종류", "해석", "결과수"], "ask_id"),
  ("app.usage_owner_ip", "SELECT ip, 처음, 근거 FROM ops.usage_owner_ip", ["ip", "처음", "근거"], None),
]
RL = ["log_sk", "때", "ip", "내부", "경로", "질의", "동작", "상태", "밀리", "나라", "ua", "리퍼러", "요청번호", "오류"]


def q(c): return ", ".join(f'"{x}"' for x in c)


def copy(ms, pg, table, sql, cols):
    cur = ms.cursor(); cur.execute("SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; " + sql)
    while cur.description is None and cur.nextset(): pass
    n = 0
    with pg.cursor() as c, c.copy(f"COPY {table} ({q(cols)}) FROM STDIN") as cp:
        while True:
            rows = cur.fetchmany(5000)
            if not rows: break
            for r in rows: cp.write_row(r)
            n += len(rows)
    return n


GAP = 5_000_000   # 넘어간 뒤 새 줄 번호를 적재DB 번호보다 이만큼 위에서 시작 — 넘어가는 사이 적재DB 에 들어간 줄을 나중에 이어 붙여도 번호가 안 겹친다


def reqlog(ms, pg):
    """접속 기록 이어 붙이기 — 적재DB log_sk 가 마지막으로 옮긴 것보다 큰 것만(app.copy_state). 넘어간 뒤에도 돌릴 수 있다(번호가 안 겹침)."""
    with pg.cursor() as c:
        c.execute("SELECT last FROM app.copy_state WHERE name = 'req_log'"); r = c.fetchone()
    끝 = r[0] if r else 0
    n = copy(ms, pg, "app.req_log", f"SELECT {', '.join(RL)} FROM ops.req_log WHERE log_sk > {int(끝)} ORDER BY log_sk", RL)
    cur = ms.cursor(); cur.execute("SELECT ISNULL(MAX(log_sk), 0) FROM ops.req_log"); 새끝 = max(int(cur.fetchone()[0]), 끝)
    with pg.cursor() as c:
        c.execute("INSERT INTO app.copy_state VALUES ('req_log', %s) ON CONFLICT (name) DO UPDATE SET last = EXCLUDED.last", (새끝,))
        # 일련번호는 적재DB 끝 + GAP 보다 아래로 내려가지 않게(이미 위면 그대로)
        c.execute("SELECT setval(pg_get_serial_sequence('app.req_log', 'log_sk'), GREATEST((SELECT coalesce(max(log_sk), 0) FROM app.req_log), %s))", (새끝 + GAP,))
    pg.commit(); print(f"  app.req_log: +{n:,}줄 (적재DB log_sk {끝:,} → {새끝:,})", flush=True)


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--check", action="store_true")
    ap.add_argument("--reqlog-only", action="store_true", help="접속 기록만 이어 붙임(넘어간 뒤에도)")
    ap.add_argument("--cutover", action="store_true", help="넘어감 표시(app.cutover) — 그 뒤로 작은 표는 덮어쓰지 않는다")
    a = ap.parse_args()
    e = env(); ms = ms_conn(e); pg = pg_conn(e)
    with pg.cursor() as c: c.execute(DDL)
    pg.commit()
    if a.check:
        for t, sql, cols, _ in SMALL + [("app.req_log", "SELECT 1 FROM ops.req_log", RL, None), ("app.usage_hour", "SELECT 1 FROM ops.usage_hour", [], None)]:
            src = sql.split(" FROM ")[-1].split()[0]
            cur = ms.cursor(); cur.execute(f"SELECT COUNT_BIG(*) FROM {src}"); m = cur.fetchone()[0]
            with pg.cursor() as c: c.execute(f"SELECT count(*) FROM {t}"); p = c.fetchone()[0]
            print(f"  {t:22s} 적재DB {m:>10,} · 서비스DB {p:>10,}{'' if m == p else '  ← 다름'}")
        return
    if a.reqlog_only:
        reqlog(ms, pg); return
    if a.cutover:
        with pg.cursor() as c: c.execute("INSERT INTO app.cutover (note) VALUES ('svc_mode app: true')")
        pg.commit(); print("넘어감 표시함"); return
    with pg.cursor() as c:
        c.execute("SELECT at FROM app.cutover ORDER BY at DESC LIMIT 1"); cut = c.fetchone()
    if cut:
        print(f"이미 넘어감({cut[0]}) — app.* 가 원본이라 아무것도 덮어쓰지 않습니다"); return
    t = time.time()
    # 작은 표: 비어 있을 때만 통째로(넘어가기 전에는 몇 번이든 다시 — 비우고 다시)
    for table, sql, cols, seq in SMALL:
        with pg.cursor() as c: c.execute(f"TRUNCATE {table}")
        n = copy(ms, pg, table, sql, cols)
        if seq:
            with pg.cursor() as c:
                c.execute(f"SELECT setval(pg_get_serial_sequence('{table}', '{seq}'), GREATEST((SELECT coalesce(max({seq}), 0) FROM {table}), 1))")
        pg.commit(); print(f"  {table}: {n:,}줄", flush=True)
    # 이용현황: 통째로(작다 — 시간 단위 셈)
    with pg.cursor() as c: c.execute("TRUNCATE app.usage_hour")
    n = copy(ms, pg, "app.usage_hour", "SELECT 시각, 동작, 횟수, 갈래 FROM ops.usage_hour", ["시각", "동작", "횟수", "갈래"]); pg.commit()
    print(f"  app.usage_hour: {n:,}줄", flush=True)
    reqlog(ms, pg)
    print(f"끝 · {time.time() - t:.0f}초")


if __name__ == "__main__":
    main()
