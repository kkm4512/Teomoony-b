#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""nation_lawd - 법정동(읍면동 8자리 앞자리)마다 받는 적재 스크립트를 전국으로 여러 개 동시에 (2026-10-25 사장님 "VWorld 도 운영등급")
  py nation_lawd.py --tag cadastral --workers 6 -- load_cadastral.py
  ★ 단위 = 법정동코드 앞 8자리(시군구 5 + 읍면동 3). 리가 있는 읍 · 면도 한 번에(pnu:like 는 앞자리 일치).
  ★ 서울과 이미 받은 시군구(분당 · 수성 · 안양 만안 · 동안)는 뺀다. 끝낸 곳은 _nation_<tag>_done.txt."""
import argparse, os, subprocess, sys, threading, time
from concurrent.futures import ThreadPoolExecutor
HERE = os.path.dirname(os.path.abspath(__file__))
from svc_publish import env, ms_conn
이미 = ("11", "27260", "41135", "41171", "41173")

def main():
    i = sys.argv.index("--"); mine, cmd = sys.argv[1:i], sys.argv[i + 1:]
    ap = argparse.ArgumentParser(); ap.add_argument("--tag", required=True); ap.add_argument("--workers", type=int, default=6); a = ap.parse_args(mine)
    cur = ms_conn(env()).cursor()
    cur.execute("""SELECT LEFT(lawd_cd, 8), MIN(sido_nm + ' ' + ISNULL(sgg_nm, '') + ' ' + ISNULL(emd_nm, ''))
                     FROM meta.lawd_code WHERE emd_nm IS NOT NULL AND ISNULL(is_abolished, 0) = 0 GROUP BY LEFT(lawd_cd, 8)""")
    codes = {c: n for c, n in cur.fetchall() if not c.startswith(이미)}
    done_f = os.path.join(HERE, f"_nation_{a.tag}_done.txt")
    done = set(open(done_f, encoding="utf-8").read().split()) if os.path.exists(done_f) else set()
    todo = sorted(c for c in codes if c not in done)
    print(f"[{a.tag}] 읍면동 {len(codes)} · 끝낸 곳 {len(done)} · 남은 곳 {len(todo)} · 동시 {a.workers} · {' '.join(cmd)}", flush=True)
    lock = threading.Lock(); t0 = time.time(); n = [0]; bad = []
    def one(c):
        st = time.time()
        r = subprocess.run([sys.executable, os.path.join(HERE, cmd[0])] + cmd[1:] + ["--lawd", c], cwd=HERE, capture_output=True, text=True, encoding="utf-8", errors="replace")
        with lock:
            n[0] += 1
            if r.returncode != 0:
                bad.append(c); print(f"  !! {c} {codes[c]} 종료코드 {r.returncode}: {(r.stderr or r.stdout)[-300:]}", flush=True); return
            open(done_f, "a", encoding="utf-8").write(c + "\n")
            if n[0] % 20 == 0 or time.time() - st > 600:
                el = time.time() - t0
                print(f"  ✔ [{time.strftime('%H:%M:%S')}] {n[0]}/{len(todo)} · {c} {codes[c]} {int(time.time() - st)}초 · 남은 예상 {el / n[0] * (len(todo) - n[0]) / 3600:.1f}시간", flush=True)
    with ThreadPoolExecutor(a.workers) as ex: list(ex.map(one, todo))
    print(f"끝 · {int(time.time() - t0)}초 · 실패 {len(bad)} {' '.join(bad)}", flush=True)

if __name__ == "__main__":
    main()
