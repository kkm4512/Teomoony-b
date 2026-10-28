# -*- coding: utf-8 -*-
"""rtms_recent - 실거래 **최근 3개월**만 전국 다시 받기(매일 새벽 · 2026-10-28 수집 일정)
  실거래는 계약 뒤 30일 안에 신고 · 해제(취소) · 정정이 뒤늦게 들어온다 → 이번 달 · 지난달 · 그 전달을 매일 다시 본다.
  새 거래는 넣고, 해제 표시는 고친다(load_rtms 가 nat_key 로). 끝에 단지 다시 잇기(load_rtms --rematch-only) 한 번.
  py rtms_recent.py [--months 3] [--workers 8]
  ★ 종료코드: 0 성공 · 1 일부 시군구 실패(로그에 목록)"""
import argparse, os, subprocess, sys, time, threading
from concurrent.futures import ThreadPoolExecutor
from svc_publish import env, ms_conn
HERE = os.path.dirname(os.path.abspath(__file__))
ap = argparse.ArgumentParser(); ap.add_argument("--months", type=int, default=3); ap.add_argument("--workers", type=int, default=8); a = ap.parse_args()
t = time.localtime(); y, m = t.tm_year, t.tm_mon
for _ in range(a.months - 1):
    m -= 1
    if m == 0: y, m = y - 1, 12
frm, to = f"{y}{m:02d}", time.strftime("%Y%m")
cur = ms_conn(env()).cursor()
cur.execute("""SELECT sgg_cd FROM meta.lawd_code WHERE emd_nm IS NULL AND ri_nm IS NULL AND sgg_nm IS NOT NULL AND ISNULL(is_abolished, 0) = 0""")
codes = {r[0] for r in cur.fetchall()}
부모 = {c for c in codes if c.endswith("0") and any(o != c and o[:4] == c[:4] for o in codes)}
잎 = sorted(c for c in codes if c not in 부모)
cur.execute("SELECT COUNT_BIG(*), SUM(CASE WHEN is_canceled = 1 THEN 1 ELSE 0 END) FROM silver.rtms_trade"); 전 = cur.fetchone()
print(f"실거래 최근 {a.months}개월 {frm}~{to} · 시군구 {len(잎)} · 동시 {a.workers}", flush=True)
lock = threading.Lock(); 실패 = []; t0 = time.time()
def one(sgg):
    for extra in ([], ["--kind", "SILV_TRADE"]):
        r = subprocess.run([sys.executable, os.path.join(HERE, "load_rtms.py"), "--sgg", sgg, "--from", frm, "--to", to, "--no-match"] + extra,
                           cwd=HERE, capture_output=True, text=True, encoding="utf-8", errors="replace")
        if r.returncode != 0:
            with lock: 실패.append(sgg); print(f"  !! {sgg} {' '.join(extra) or '10종'} 종료코드 {r.returncode} · {(r.stderr or r.stdout)[-200:]}", flush=True)
            return
with ThreadPoolExecutor(a.workers) as ex: list(ex.map(one, 잎))
print(f"받기 끝 · {int(time.time() - t0)}초 · 실패 {len(실패)}곳", flush=True)
r = subprocess.run([sys.executable, os.path.join(HERE, "load_rtms.py"), "--rematch-only"], cwd=HERE, capture_output=True, text=True, encoding="utf-8", errors="replace")
print((r.stdout or "")[-1500:], flush=True)
cur = ms_conn(env()).cursor()
cur.execute("SELECT COUNT_BIG(*), SUM(CASE WHEN is_canceled = 1 THEN 1 ELSE 0 END) FROM silver.rtms_trade"); 후 = cur.fetchone()
print(f"결과: 새로 {후[0] - 전[0]:,}건 · 해제 표시 {후[1] - 전[1]:+,}건 · 전체 {후[0]:,}", flush=True)
sys.exit(1 if 실패 or r.returncode != 0 else 0)
