# -*- coding: utf-8 -*-
"""_targets - 적재 **대상** 시군구를 한 곳(meta.load_target → meta.v_target_sgg, 339)에서 읽는다  2026-10-24

  사장님 "전국구로 넓혀 가자" 1단계. 적재 스크립트마다 서울 25구 · 안양 목록을 코드에 적어 두던 것을 걷어 낸다.
  지역을 늘리려면 meta.load_target 에 시군구 한 줄(enabled=1)을 넣는다 — 스크립트는 고치지 않는다.

  from _targets import 대상시군구
  대상시군구()            -> ['11110', ..., '41171', '41173']   (단지가 붙는 시군구 — 일반구는 일반구로)
  대상시군구(시로=True)   -> ['11110', ..., '41170']            (시 단위로 받는 자료: 일반구는 그 시 하나로 — 어린이집 등)

  ★ DB 에 닿으면 DB 에서, 아니면(장치 VM 처럼 DB 가 안 보이는 곳) etl/_export/target_sgg.txt 에서 읽는다.
    그 파일은 집 PC 에서 /api/_export?name=target_sgg 가 만든다. 둘 다 없으면 멈춘다 — 목록을 지어내지 않는다.
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
EXPORT = os.path.join(HERE, "_export", "target_sgg.txt")


def _env():
    p = os.path.join(HERE, "..", ".env"); d = {}
    if os.path.exists(p):
        for ln in open(p, encoding="utf-8"):
            ln = ln.strip()
            if ln and not ln.startswith("#") and "=" in ln:
                k, v = ln.split("=", 1); d[k.strip()] = v.strip().strip('"').strip("'")
    return d


def _from_db(cur=None):
    if cur is None:
        try:
            import pymssql
        except ImportError:
            return None
        e = _env()
        try:
            conn = pymssql.connect(server=e.get("DB_HOST", "127.0.0.1"), port=int(e.get("DB_PORT", 11433)),
                                   user=e.get("DB_USER", "sa"), password=e.get("DB_PASSWORD", ""),
                                   database=e.get("DB_NAME", "Teomoony"), charset="UTF-8", login_timeout=5)
        except Exception:
            return None
        cur = conn.cursor()
    cur.execute("SELECT sgg_cd, 시 FROM meta.v_target_sgg ORDER BY sgg_cd")
    return [(r[0].strip(), r[1].strip()) for r in cur.fetchall()]


def _from_file():
    if not os.path.exists(EXPORT):
        return None
    out = []
    for ln in open(EXPORT, encoding="utf-8"):
        p = ln.rstrip("\n").split("\t")
        if len(p) >= 2 and len(p[0].strip()) == 5:
            out.append((p[0].strip(), p[1].strip()))
    return out or None


def 대상시군구(시로=False, cur=None):
    rows = _from_db(cur)
    if rows is None:
        rows = _from_file()
    if not rows:
        sys.exit("적재 대상 시군구를 읽지 못했습니다 — DB(meta.v_target_sgg)도 _export/target_sgg.txt 도 없습니다")
    if not 시로:
        return [s for s, _ in rows]
    # 시 단위: 일반구(끝자리 ≠ 0)는 그 시(앞 4자리 + 0)로 모은다
    return sorted({(시 if s[-1] != "0" else s) for s, 시 in rows})


if __name__ == "__main__":
    print(" ".join(대상시군구(시로="--si" in sys.argv)))
