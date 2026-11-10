#!/usr/bin/env python3
"""coverage_gate - 받은 범위표(339 meta.usp_refresh_coverage) 다시 세기에 간격을 둔다 (2026-11-10)

★ 왜: 작업 감시기의 범위걸기가 z- 아닌 작업이 성공할 때마다 z-coverage-par 를 건다(10-24 "약 20초"라 넉넉히).
  전국 자료가 늘어 지금은 한 번에 3~11분 · 11-10 하루 8번 · 지금까지 982번 — 적재DB CPU 상위였다.
  감시기 코드(_job_runner.py)는 수집 일정이 뒷줄에 늘 떠 있어 restart 가 미뤄진다 → 같은 이름을 _jobs_linux.json 에서 이 문지기로 덮는다.

  z-coverage-par  = coverage_gate.py --gap 60   (적재 뒤 자동 · 마지막으로 센 지 60분 안이면 건너뜀 = 종료코드 3)
  cl-coverage-par = coverage_gate.py --gap 0    (수집 일정 매시 :50 · 늘 센다 → 범위표는 늦어도 한 시간 안에 맞는다)
  실행 경로는 감시기와 같다(run_sql = docker exec sqlcmd -b). 성공했을 때만 _queue/_coverage_at 을 새로 쓴다.
"""
import argparse, os, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import _job_runner as R

STAMP = os.path.join(R.QDIR, "_coverage_at")


def last_at():
    try:
        return os.path.getmtime(STAMP)
    except OSError:
        return 0.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gap", type=float, default=60, help="마지막으로 센 뒤 이 분이 안 지났으면 건너뜀(0 = 늘 센다)")
    a = ap.parse_args()
    지난 = (time.time() - last_at()) / 60
    if a.gap and 지난 < a.gap:
        print(f"건너뜀 — 범위표를 {지난:.0f}분 전에 셌다({a.gap:.0f}분 안). 매시 :50 수집 일정이 다시 센다.", flush=True)
        sys.exit(3)
    t = time.time()
    rc = R.run_sql(os.path.join(R.SQLDIR, "339_coverage_run.sql"), "339_coverage_run", sys.stdout)
    if rc == 0:
        with open(STAMP, "w", encoding="utf-8") as f:
            f.write(time.strftime("%Y-%m-%d %H:%M:%S") + "\n")
    print(f"\n범위표 다시 세기 · 종료코드 {rc} · {time.time() - t:.0f}초", flush=True)
    sys.exit(rc)


if __name__ == "__main__":
    main()
