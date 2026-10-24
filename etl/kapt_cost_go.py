# -*- coding: utf-8 -*-
"""kapt_cost_go - K-apt 관리비(31 오퍼레이션)를 구마다 load_kapt_cost.py 로 받는다  2026-10-23 (사장님 "나머지도 ㄱㄱ")

  py kapt_cost_go.py --months 2 --workers 4
  py kapt_cost_go.py --ym 202608 --sgg 11290

★ 구 하나라도 실패하면 종료코드 1. 기본은 적재 대상 시군구 전부(meta.load_target · 2026-10-24) — 빼려면 --sgg 로 고른다.
"""
import argparse, os, subprocess, sys, threading, time
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
lock = threading.Lock()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--months", type=int)
    ap.add_argument("--ym", action="append")
    ap.add_argument("--from", dest="ym_from", help="YYYYMM — 과거 이력(2026-10-24 사장님 '관리비 전부'): 이 달부터 오래된 순으로")
    ap.add_argument("--to", dest="ym_to")
    ap.add_argument("--sgg", nargs="*", default=None)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--rps", type=float, default=10.0, help="구 하나(프로세스)의 초당 호출 수 — 합은 workers × rps")
    ap.add_argument("--threads", type=int, default=8, help="구 하나 안에서 오퍼레이션을 같이 부를 스레드 수(load_kapt_cost --threads)")
    a = ap.parse_args()
    sys.path.insert(0, HERE)
    from _targets import 대상시군구
    gus = list(a.sgg) if a.sgg else 대상시군구()   # 2026-10-24: 서울 25구 목록 → 적재 대상 시군구(meta.v_target_sgg)
    when = (["--months", str(a.months)] if a.months else []) + sum([["--ym", y] for y in (a.ym or [])], []) \
         + (["--from", a.ym_from, "--to", a.ym_to] if a.ym_from and a.ym_to else [])
    print(f"관리비 · {' '.join(when)} · {len(gus)}구 · 스레드 {a.workers}", flush=True)
    t0 = time.time(); bad = []
    def one(sgg):
        st = time.time()
        p = subprocess.run([sys.executable, os.path.join(HERE, "load_kapt_cost.py"), "--sgg", sgg, "--threads", str(a.threads), "--rps", str(a.rps)] + when,
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
