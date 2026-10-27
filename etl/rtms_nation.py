#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""rtms_nation - 실거래 전국 전부(매매 2006.01~ · 전월세 2011.01~ · 분양권) — 시군구마다 load_rtms.py 를 여러 개 동시에 (2026-10-25 사장님
  "실거래는 좀 중요해서 다 채워넣고 싶은데" · "공공은 전부 운영키라 호출제한이 없다고 봐도 돼")
  py rtms_nation.py --workers 8 [--to 202610]

  ★ 시군구 = meta.lawd_code 의 시군구 줄 중 **잎**(일반구가 있는 시는 일반구만 — 앞 4자리가 같은 다른 코드가 있고 끝이 0 이면 부모).
  ★ 이미 다 받은 29곳(서울 25 · 안양 만안 · 동안 · 분당 · 수성)은 건너뛴다. 끝낸 곳은 _rtms_nation_done.txt — 다시 돌리면 이어서.
  ★ 단지 매칭은 하지 않는다(--no-match) — 그 지역 대장 · 필지가 들어온 뒤 load_rtms.py --rematch-only 로 한 번에.
"""
import argparse, os, subprocess, sys, time, threading
from concurrent.futures import ThreadPoolExecutor
import pymssql
HERE = os.path.dirname(os.path.abspath(__file__))
from svc_publish import env, ms_conn

DONE_FILE = os.path.join(HERE, "_rtms_nation_done.txt")
이미 = {"27260", "41135", "41171", "41173"}

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--workers", type=int, default=8); ap.add_argument("--to", default=time.strftime("%Y%m"))
    ap.add_argument("--only", nargs="*")
    a = ap.parse_args()
    ms = ms_conn(env()); cur = ms.cursor()
    cur.execute("""SELECT sgg_cd, full_nm FROM meta.lawd_code
                    WHERE emd_nm IS NULL AND ri_nm IS NULL AND sgg_nm IS NOT NULL AND ISNULL(is_abolished, 0) = 0""")
    rows = cur.fetchall()
    codes = {r[0]: r[1] for r in rows}
    부모 = {c for c in codes if c.endswith("0") and any(o != c and o[:4] == c[:4] for o in codes)}
    잎 = sorted(c for c in codes if c not in 부모 and not c.startswith("11") and c not in 이미)
    if a.only: 잎 = [c for c in 잎 if c in a.only]
    done = set(open(DONE_FILE, encoding="utf-8").read().split()) if os.path.exists(DONE_FILE) else set()
    todo = [c for c in 잎 if c not in done]
    print(f"시군구(잎) {len(잎)} · 끝낸 곳 {len(done)} · 남은 곳 {len(todo)} · 동시 {a.workers} · ~{a.to}", flush=True)
    lock = threading.Lock(); t0 = time.time(); n = [0]
    def one(sgg):
        st = time.time()
        for extra in ([], ["--kind", "SILV_TRADE"]):
            r = subprocess.run([sys.executable, os.path.join(HERE, "load_rtms.py"), "--sgg", sgg, "--from", "200601", "--to", a.to, "--no-match"] + extra,
                               cwd=HERE, capture_output=True, text=True, encoding="utf-8", errors="replace")
            if r.returncode != 0:
                with lock: print(f"  !! {sgg} {codes[sgg]} {' '.join(extra) or '10종'} 종료코드 {r.returncode}\n     {(r.stderr or r.stdout)[-400:]}", flush=True)
                return
        with lock:
            n[0] += 1
            open(DONE_FILE, "a", encoding="utf-8").write(sgg + "\n")
            el = time.time() - t0
            print(f"  ✔ [{time.strftime('%H:%M:%S')}] {sgg} {codes[sgg]} · {int(time.time() - st)}초 · {n[0]}/{len(todo)} · 남은 예상 {int(el / n[0] * (len(todo) - n[0]) / 3600 * 10) / 10}시간", flush=True)
    with ThreadPoolExecutor(a.workers) as ex:
        list(ex.map(one, todo))
    print(f"끝 · {int(time.time() - t0)}초", flush=True)

if __name__ == "__main__":
    main()
