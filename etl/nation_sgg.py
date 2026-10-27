#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""nation_sgg - 시군구마다 받는 적재 스크립트를 전국 시군구(잎)로 여러 개 동시에 (2026-10-25 사장님 "병렬로 뭐 돌릴만한 거 없나?")
  py nation_sgg.py --tag kapt   --workers 4 -- load_kapt.py --sleep 0.3
  py nation_sgg.py --tag kinder --workers 4 -- load_kinder.py
  ★ 시군구(잎) = rtms_nation 과 같은 규칙. 끝낸 곳은 _nation_<tag>_done.txt — 다시 돌리면 이어서. 서울은 --with-seoul 일 때만."""
import argparse, os, subprocess, sys, threading, time
from concurrent.futures import ThreadPoolExecutor
HERE = os.path.dirname(os.path.abspath(__file__))
from svc_publish import env, ms_conn

def 잎시군구(서울=False):
    cur = ms_conn(env()).cursor()
    cur.execute("SELECT sgg_cd, full_nm FROM meta.lawd_code WHERE emd_nm IS NULL AND ri_nm IS NULL AND sgg_nm IS NOT NULL AND ISNULL(is_abolished, 0) = 0")
    codes = dict(cur.fetchall())
    부모 = {c for c in codes if c.endswith("0") and any(o != c and o[:4] == c[:4] for o in codes)}
    return {c: n for c, n in sorted(codes.items()) if c not in 부모 and (서울 or not c.startswith("11"))}

def main():
    i = sys.argv.index("--"); mine, cmd = sys.argv[1:i], sys.argv[i + 1:]
    ap = argparse.ArgumentParser(); ap.add_argument("--tag", required=True); ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--with-seoul", action="store_true"); a = ap.parse_args(mine)
    codes = 잎시군구(a.with_seoul)
    done_f = os.path.join(HERE, f"_nation_{a.tag}_done.txt")
    done = set(open(done_f, encoding="utf-8").read().split()) if os.path.exists(done_f) else set()
    todo = [c for c in codes if c not in done]
    print(f"[{a.tag}] 시군구 {len(codes)} · 끝낸 곳 {len(done)} · 남은 곳 {len(todo)} · 동시 {a.workers} · {' '.join(cmd)}", flush=True)
    lock = threading.Lock(); t0 = time.time(); n = [0]; bad = []
    def one(sgg):
        st = time.time()
        r = subprocess.run([sys.executable, os.path.join(HERE, cmd[0])] + cmd[1:] + ["--sgg", sgg], cwd=HERE, capture_output=True, text=True, encoding="utf-8", errors="replace")
        with lock:
            n[0] += 1
            if r.returncode != 0:
                bad.append(sgg); print(f"  !! {sgg} {codes[sgg]} 종료코드 {r.returncode}: {(r.stderr or r.stdout)[-300:]}", flush=True); return
            open(done_f, "a", encoding="utf-8").write(sgg + "\n")
            tail = [x for x in (r.stdout or "").strip().splitlines() if x.strip()][-1:] 
            print(f"  ✔ [{time.strftime('%H:%M:%S')}] {sgg} {codes[sgg]} · {int(time.time() - st)}초 · {n[0]}/{len(todo)} · {tail[0][:120] if tail else ''}", flush=True)
    with ThreadPoolExecutor(a.workers) as ex: list(ex.map(one, todo))
    print(f"끝 · {int(time.time() - t0)}초 · 실패 {len(bad)} {' '.join(bad)}", flush=True)

if __name__ == "__main__":
    main()
