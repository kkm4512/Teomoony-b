#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""rtms_monthly - 실거래 매달 바로잡기 (2026-11-20 사장님 "ㄱㄱ")

  매일 받기(rtms_recent)는 최근 3개월만 다시 본다 → 그보다 늦게 생기는 변경(늦은 동 · 등기일 · 지번 변경 · 정정 · 철회)을 못 본다.
  한 달에 한 번 최근 24개월을 통째로 다시 받아 원천과 맞춘다.
    1) rtms_go.py   최근 24개월 · 10종목 다시 받기(4개 동시 · 받기 제한이면 쉬고 다시) — 값 칸도 원천대로(load_rtms 11-20)
    2) rtms_go.py   같은 기간 분양권(SILV_TRADE — rtms_go 기본 종목에 없다)
    3) rtms_gone.py 같은 기간 원천 ↔ 적재 대조(같은 순번 키 · 받기 OK 묶음만)
    4) 420          대조에서 사라진 줄 격리(ops.rtms_gone_bak · 키 그대로인 줄만 · 대조 끝난 지 90분 안)
    5) svc_trade_stale.py --fix  실거래 수가 바뀐 단지 상세 다시 담기
  받기가 실패하면 대조 · 격리는 하지 않는다(일부만 받은 상태로 '사라졌다' 고 하지 않게) · 대조가 다 안 되면 격리하지 않는다. 다시 담기는 늘 한다.
  종료코드: 0 성공 · 1 실패(로그에 어느 단계인지)

  python rtms_monthly.py [--months 24] [--dry]
"""
import argparse, os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))


def 몇달전(n):
    t = time.localtime(); y, m = t.tm_year, t.tm_mon
    for _ in range(n - 1):
        m -= 1
        if m == 0: y, m = y - 1, 12
    return f"{y}{m:02d}", time.strftime("%Y%m")


def 돌리기(이름, cmd, dry):
    print(f"\n[{time.strftime('%H:%M:%S')}] ▶ {이름}: {' '.join(cmd)}", flush=True)
    if dry: return 0
    t = time.time(); r = subprocess.run([sys.executable] + cmd, cwd=HERE)
    print(f"[{time.strftime('%H:%M:%S')}] ◀ {이름} 종료코드 {r.returncode} · {(time.time()-t)/60:.1f}분", flush=True)
    return r.returncode


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--months", type=int, default=24); ap.add_argument("--dry", action="store_true"); a = ap.parse_args()
    frm, to = 몇달전(a.months)
    print(f"실거래 매달 바로잡기 · {frm} ~ {to} ({a.months}개월)", flush=True)
    받기 = [돌리기("다시 받기(10종목)", ["rtms_go.py", "--from", frm, "--to", to, "--workers", "4"], a.dry),
            돌리기("다시 받기(분양권)", ["rtms_go.py", "--from", frm, "--to", to, "--workers", "4", "--kind", "SILV_TRADE"], a.dry)]
    실패 = [n for n, rc in zip(("다시 받기(10종목)", "다시 받기(분양권)"), 받기) if rc != 0]
    if not 실패:
        rc = 돌리기("원천 ↔ 적재 대조", ["rtms_gone.py", "--from", frm, "--to", to, "--workers", "6"], a.dry)
        if rc == 0:
            if 돌리기("사라진 줄 격리(420)", ["ms_q.py", os.path.join("..", "deploy", "sql", "420_rtms_gone_quarantine.sql")], a.dry) != 0: 실패.append("격리")
        else:
            실패.append("대조"); print("\n!! 대조가 다 되지 않아(받기 실패 묶음 등) 격리는 하지 않는다", flush=True)
    else:
        print(f"\n!! {', '.join(실패)} 실패 — 대조 · 격리는 하지 않는다(일부만 받은 상태로 '사라졌다' 고 하지 않게)", flush=True)
    if 돌리기("단지 상세 다시 담기", ["svc_trade_stale.py", "--fix"], a.dry) != 0: 실패.append("다시 담기")   # 받은 만큼은 화면에 반영
    print(f"\n[{time.strftime('%H:%M:%S')}] 끝 — " + ("모두 성공" if not 실패 else "실패: " + ", ".join(실패)), flush=True)
    sys.exit(1 if 실패 else 0)

if __name__ == "__main__":
    main()
