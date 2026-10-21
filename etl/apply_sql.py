# -*- coding: utf-8 -*-
"""deploy/sql 의 파일을 pymssql 로 적용한다 — 뒷줄(-bg) 전용 길  2026-10-20

★ 왜 있나: 감시기의 sql.<이름> 작업은 **앞줄 전용**이다. 앞줄이 30시간 차
  있으면 DDL 하나를 넣으려고 30시간을 기다려야 한다. 뒷줄에 태우려면
  argv 로 돌 수 있어야 하는데, sqlcmd 를 쓰면 비밀번호가 명령줄에 올라간다
  (프로세스 목록에 보인다). 그래서 .env 를 직접 읽는 pymssql 로 간다.

★ GO 로 배치를 나눈다 — pymssql 은 GO 를 모른다.
★ 읽기/만들기만 쓴다. 지우는 SQL 은 여기 태우지 않는다.
★ 한 배치가 실패하면 **거기서 멈춘다.** 뒤 배치를 계속 밀면 반쯤 만들어진
  상태가 되고, 그게 조용히 틀린 상태다.
"""
import io, os, re, sys
import pymssql

HERE   = os.path.dirname(os.path.abspath(__file__))
SQLDIR = os.path.join(HERE, "..", "deploy", "sql")
ENV    = os.path.join(HERE, "..", ".env")


def env():
    d = {}
    for line in io.open(ENV, encoding="utf-8-sig"):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1); d[k.strip()] = v.strip()
    return d


def main():
    names = sys.argv[1:]
    if not names:
        sys.exit("쓰기: py apply_sql.py 205_academy.sql 206_academy_view.sql ...")
    e = env()
    conn = pymssql.connect(server=e.get("DB_HOST", "127.0.0.1"),
                           port=int(e.get("DB_PORT", 11433)),
                           user=e.get("DB_USER", "sa"),
                           password=e.get("DB_PASSWORD", ""),
                           database=e.get("DB_NAME", "Teomoony"),
                           charset="UTF-8", autocommit=True)
    cur = conn.cursor()
    for nm in names:
        path = nm if os.path.isabs(nm) else os.path.join(SQLDIR, nm)
        if not os.path.isfile(path):
            sys.exit(f"없는 파일: {path}")
        sql = io.open(path, encoding="utf-8").read()
        배치 = [b.strip() for b in re.split(r"(?mi)^\s*GO\s*$", sql) if b.strip()]
        print(f"\n{os.path.basename(path)} — 배치 {len(배치)}개", flush=True)
        for i, b in enumerate(배치, 1):
            첫줄 = b.split("\n")[0][:70]
            try:
                cur.execute(b)
                while True:                     # 결과집합이 있으면 비운다
                    try:
                        rows = cur.fetchall()
                    except Exception:
                        rows = None
                    if rows:
                        for r in rows[:15]:
                            print("    " + " | ".join("NULL" if v is None else str(v)[:40]
                                                      for v in r))
                        if len(rows) > 15:
                            print(f"    ... 외 {len(rows)-15}행")
                    if not cur.nextset():
                        break
                print(f"  [{i}/{len(배치)}] OK  {첫줄}", flush=True)
            except Exception as ex:
                print(f"  [{i}/{len(배치)}] ★ 실패  {첫줄}")
                print(f"      {type(ex).__name__}: {ex}")
                sys.exit(f"\n{os.path.basename(path)} {i}번째 배치에서 멈췄습니다 "
                         "— 뒤 배치는 돌리지 않았습니다.")
    conn.close()
    print("\n전부 적용했습니다.")


if __name__ == "__main__":
    main()
