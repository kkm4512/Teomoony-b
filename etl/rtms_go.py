# -*- coding: utf-8 -*-
"""rtms_go - 실거래(RTMS) 를 **시군구 × 연도** 단위로 병렬 적재한다  (2026-10-24)

  사장님 "데이터 받아오는 키는 전부 운영키 · 적재할 때는 스레드를 최대한". rtms_seoul.py 는 병렬 단위가 **구**라
  안양(2개 구)을 받으면 스레드가 2개뿐이었다. 여기서는 구 × 연도로 잘라 스레드를 다 쓴다.
  ★ 조각마다 load_rtms.py --no-match 로 받고, **매칭은 끝에 한 번만**(--rematch-only) — 조각마다 매칭하면 같은 표를 서로 잡는다.
  ★ 시군구를 안 주면 적재 대상 시군구 전부(meta.v_target_sgg · _targets.py).

  py rtms_go.py --sgg 41171 41173 --from 200601 --to 202312 --workers 16
  py rtms_go.py --from 202610 --to 202610                 # 대상 전부 · 이번 달만
"""
import argparse, os, subprocess, sys, threading, time
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
lock = threading.Lock()


def ts():
    return time.strftime("%H:%M:%S")


def 조각(ym_from, ym_to):
    """[from, to] 를 연도 단위 (시작월, 끝월) 로 자른다"""
    y0, y1 = int(ym_from[:4]), int(ym_to[:4])
    out = []
    for y in range(y0, y1 + 1):
        a = ym_from if y == y0 else f"{y}01"
        b = ym_to if y == y1 else f"{y}12"
        out.append((a, b))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sgg", nargs="*")
    ap.add_argument("--from", dest="ym_from", required=True)
    ap.add_argument("--to", dest="ym_to", required=True)
    ap.add_argument("--workers", type=int, default=16)
    ap.add_argument("--kind", action="append")
    ap.add_argument("--no-rematch", action="store_true")
    a = ap.parse_args()
    if not a.sgg:
        from _targets import 대상시군구
        a.sgg = 대상시군구()
    일 = [(s, f, t) for s in a.sgg for f, t in 조각(a.ym_from, a.ym_to)]
    print(f"[{ts()}] 시군구 {len(a.sgg)} · {a.ym_from}~{a.ym_to} · 조각 {len(일)} · 스레드 {a.workers}", flush=True)
    t0 = time.time(); 셈 = {"n": 0, "bad": []}

    def one(u):
        s, f, t = u
        st = time.time()
        cmd = [sys.executable, os.path.join(HERE, "load_rtms.py"), "--sgg", s, "--from", f, "--to", t, "--no-match"]
        for k in (a.kind or []):
            cmd += ["--kind", k]
        p = subprocess.run(cmd, cwd=HERE, capture_output=True, text=True, encoding="utf-8", errors="replace")
        out = ((p.stdout or "") + (p.stderr or "")).strip().splitlines()
        with lock:
            셈["n"] += 1
            if p.returncode != 0:
                셈["bad"].append(u)
            print(f"  [{ts()}] {'OK' if p.returncode == 0 else '!!'} [{셈['n']}/{len(일)}] {s} {f}~{t} {time.time()-st:.0f}초", flush=True)
            for ln in (out[-3:] if p.returncode == 0 else out[-8:]):
                print(f"       {ln}", flush=True)

    with ThreadPoolExecutor(max_workers=a.workers) as ex:
        list(ex.map(one, 일))
    print(f"\n[{ts()}] 받기 끝 {(time.time()-t0)/60:.1f}분 · 실패 {len(셈['bad'])}", flush=True)
    for u in 셈["bad"]:
        print(f"   !! {u}")
    if not a.no_rematch:
        print(f"[{ts()}] 매칭 한 번(--rematch-only)", flush=True)
        p = subprocess.run([sys.executable, os.path.join(HERE, "load_rtms.py"), "--rematch-only"], cwd=HERE)
        print(f"[{ts()}] 매칭 종료코드 {p.returncode}", flush=True)
        if p.returncode != 0:
            sys.exit(2)          # 받기는 됐어도 매칭이 죽으면 실패로 알린다(조용히 성공으로 넘기지 않는다)
    sys.exit(1 if 셈["bad"] else 0)


if __name__ == "__main__":
    main()
