# -*- coding: utf-8 -*-
"""silv_go - 아파트 분양권·입주권 전매 실거래를 서울 25구 + 안양 2구에 받는다  2026-10-21

  py silv_go.py --from 202001 --to 202610 --workers 4

★ load_rtms.py --kind SILV_TRADE --no-match 를 구마다 부른다. 매칭 패스(전체 다시 붙이기)는 **안 돈다** —
  분양권은 단지에 안 붙이고(282 가 건너뜀) PNU 까지만 두므로 필요 없다. 구마다 돌리면 수 분씩 27번이라 뺐다.
★ 구 하나라도 실패하면 종료코드 1 — '완료' 로 끝나지 않는다.
"""
import argparse, os, subprocess, sys, threading, time
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
lock = threading.Lock()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="ym_from", default="202001")
    ap.add_argument("--to", dest="ym_to", default=time.strftime("%Y%m"))
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--sgg", nargs="*", default=None, help="받을 구만(기본: 적재 대상 시군구 전부)")
    a = ap.parse_args()
    sys.path.insert(0, HERE)
    from _targets import 대상시군구
    gus = list(a.sgg) if a.sgg else 대상시군구()   # 2026-10-24: 27구 목록 → 적재 대상 시군구(meta.v_target_sgg)
    print(f"분양권·입주권 전매 · {a.ym_from}~{a.ym_to} · {len(gus)}구 · 스레드 {a.workers}", flush=True)
    t0 = time.time(); bad = []
    def one(sgg):
        st = time.time()
        p = subprocess.run([sys.executable, os.path.join(HERE, "load_rtms.py"), "--sgg", sgg, "--from", a.ym_from,
                            "--to", a.ym_to, "--kind", "SILV_TRADE", "--no-match"],
                           cwd=HERE, capture_output=True, text=True, encoding="utf-8", errors="replace")
        out = ((p.stdout or "") + (p.stderr or "")).strip().splitlines()
        with lock:
            if p.returncode != 0: bad.append(sgg)
            print(f"  {'OK' if p.returncode == 0 else '!!'} {sgg}  {int(time.time()-st)}초", flush=True)
            for ln in [x for x in out if 'SILV_TRADE' in x or '중단' in x or 'Error' in x][-3:]: print("     " + ln, flush=True)
    with ThreadPoolExecutor(max_workers=a.workers) as ex:
        list(ex.map(one, gus))
    print(f"끝 · {int(time.time()-t0)}초 · 실패 {len(bad)}곳 {' '.join(bad)}", flush=True)
    sys.exit(1 if bad else 0)

if __name__ == "__main__":
    main()
