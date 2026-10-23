# -*- coding: utf-8 -*-
"""kapt_cost_go - K-apt 관리비(31 오퍼레이션)를 구마다 load_kapt_cost.py 로 받는다  2026-10-23 (사장님 "나머지도 ㄱㄱ")

  py kapt_cost_go.py --months 2 --workers 4
  py kapt_cost_go.py --ym 202608 --sgg 11290

★ 구 하나라도 실패하면 종료코드 1. 안양은 보류(11-235) — 기본은 서울 25구.
"""
import argparse, os, subprocess, sys, threading, time
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
SEOUL = ["11110","11140","11170","11200","11215","11230","11260","11290","11305","11320","11350","11380","11410",
         "11440","11470","11500","11530","11545","11560","11590","11620","11650","11680","11710","11740"]
lock = threading.Lock()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--months", type=int)
    ap.add_argument("--ym", action="append")
    ap.add_argument("--sgg", nargs="*", default=None)
    ap.add_argument("--workers", type=int, default=4)
    a = ap.parse_args()
    gus = [g for g in SEOUL if not a.sgg or g in a.sgg]
    when = (["--months", str(a.months)] if a.months else []) + sum([["--ym", y] for y in (a.ym or [])], [])
    print(f"관리비 · {' '.join(when)} · {len(gus)}구 · 스레드 {a.workers}", flush=True)
    t0 = time.time(); bad = []
    def one(sgg):
        st = time.time()
        p = subprocess.run([sys.executable, os.path.join(HERE, "load_kapt_cost.py"), "--sgg", sgg] + when,
                           cwd=HERE, capture_output=True, text=True, encoding="utf-8", errors="replace")
        out = ((p.stdout or "") + (p.stderr or "")).strip().splitlines()
        with lock:
            if p.returncode != 0: bad.append(sgg)
            print(f"  {'OK' if p.returncode == 0 else '!!'} {sgg}  {int(time.time()-st)}초", flush=True)
            for ln in [x for x in out if '신규' in x or '호출' in x or 'Error' in x or '단지 ' in x][-3:]: print("     " + ln, flush=True)
    with ThreadPoolExecutor(max_workers=a.workers) as ex:
        list(ex.map(one, gus))
    print(f"끝 · {int(time.time()-t0)}초 · 실패 {len(bad)}곳 {' '.join(bad)}", flush=True)
    sys.exit(1 if bad else 0)

if __name__ == "__main__":
    main()
