# -*- coding: utf-8 -*-
"""run_parallel - _jobs_extra.json 의 작업 여러 개를 **동시에** 돌린다  2026-10-21

  py run_parallel.py a-applyhome-bg ab-silv-bg ac-landuse-bg

★ 왜: 감시기의 뒷줄(-bg)은 한 번에 하나씩이다. 서로 **다른 표**를 쓰는 작업(청약홈 · 분양권 · 토지이용계획)은
  같이 돌려도 안 엉킨다. 그런 것만 묶는다 — 같은 표를 쓰는 둘을 넣으면 교착이 난다(11-150).
★ 이름은 _jobs_extra.json 에 **이미 있는 것만** 받는다(감시기와 같은 문지기). 명령을 받지 않는다.
★ 하나라도 실패하면 종료코드 1. 작업마다 로그를 logs/par_<이름>_<시각>.log 에 따로 남긴다.
"""
import io, json, os, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
LOGS = os.path.join(HERE, "..", "logs")


def main():
    names = sys.argv[1:]
    ex = json.load(io.open(os.path.join(HERE, "_jobs_extra.json"), encoding="utf-8"))
    bad = [n for n in names if n not in ex or n.startswith("par")]
    if not names or bad:
        sys.exit(f"_jobs_extra.json 에 없는 이름: {bad or '(없음)'}")
    stamp = time.strftime("%Y%m%d_%H%M%S")
    print(f"동시에: {' · '.join(names)}", flush=True)

    def one(n):
        argv = ex[n]
        if argv and argv[0] == "python": argv = [sys.executable] + argv[1:]
        lp = os.path.join(LOGS, f"par_{n}_{stamp}.log"); t0 = time.time()
        with io.open(lp, "w", encoding="utf-8") as f:
            env = dict(os.environ, PYTHONIOENCODING="utf-8", PYTHONUTF8="1")
            p = subprocess.run(argv, cwd=HERE, stdout=f, stderr=subprocess.STDOUT, env=env)
        tail = io.open(lp, encoding="utf-8", errors="replace").read().strip().splitlines()[-4:]
        return n, p.returncode, int(time.time() - t0), tail

    with ThreadPoolExecutor(max_workers=len(names)) as pool:
        rs = list(pool.map(one, names))
    fail = 0
    for n, rc, sec, tail in rs:
        print(f"  {'OK' if rc == 0 else '!!'} {n}  {sec}초  종료코드 {rc}", flush=True)
        for ln in tail: print("      " + ln, flush=True)
        fail += rc != 0
    sys.exit(1 if fail else 0)


if __name__ == "__main__":
    main()
