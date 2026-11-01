# -*- coding: utf-8 -*-
"""rtms_recent - 실거래 **최근 3개월**만 전국 다시 받기(매일 새벽 · 2026-10-28 수집 일정)
  실거래는 계약 뒤 30일 안에 신고 · 해제(취소) · 정정이 뒤늦게 들어온다 → 이번 달 · 지난달 · 그 전달을 매일 다시 본다.
  새 거래는 넣고, 해제 표시는 고친다(load_rtms 가 nat_key 로). 끝에 단지 다시 잇기(load_rtms --rematch-only) 한 번.
  py rtms_recent.py [--months 3] [--workers 8]
  ★ 종료코드: 0 성공 · 1 일부 시군구 실패(로그에 목록)
  ★ 11-01: 3시간마다(403) — 받을 때마다 ops.rtms_fetch_log 에 새 건수 · 해제 · 종류별 · 최근 계약일을 남긴다(국토부가 올리는 시각을 잼).
    새로 들어온 게 없으면 단지 다시 잇기를 건너뛴다."""
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
종류말 = {"APT_TRADE_DEV": "아파트매매", "APT_RENT": "아파트전월세", "RH_TRADE": "연립다세대매매", "RH_RENT": "연립다세대전월세", "OFFI_TRADE": "오피스텔매매",
          "OFFI_RENT": "오피스텔전월세", "SH_TRADE": "단독매매", "SH_RENT": "단독전월세", "NRG_TRADE": "상업업무", "LAND_TRADE": "토지", "SILV_TRADE": "분양권"}
def 종류셈():
    c = ms_conn(env()).cursor(); c.execute(f"SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; SELECT trade_kind, COUNT_BIG(*) FROM silver.rtms_trade WHERE deal_ymd >= '{frm}01' GROUP BY trade_kind")
    return {k: n for k, n in c.fetchall()}
종전 = 종류셈()
시작 = time.strftime("%Y-%m-%d %H:%M:%S")
try:
    cur.execute("INSERT ops.rtms_fetch_log (시작, 개월) OUTPUT inserted.id VALUES (%s, %s)", (시작, a.months)); 기록 = cur.fetchone()[0]; cur.connection.commit()
except Exception as ex:
    기록 = None; print("받기 기록 표 없음(403 전) —", type(ex).__name__, flush=True)
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
받기초 = int(time.time() - t0)
print(f"받기 끝 · {받기초}초 · 실패 {len(실패)}곳", flush=True)
cur = ms_conn(env()).cursor()
cur.execute("SELECT COUNT_BIG(*), SUM(CASE WHEN is_canceled = 1 THEN 1 ELSE 0 END) FROM silver.rtms_trade"); 후 = cur.fetchone()
새로, 해제 = 후[0] - 전[0], (후[1] or 0) - (전[1] or 0)
rc = 0
if 새로 > 0:
    r = subprocess.run([sys.executable, os.path.join(HERE, "load_rtms.py"), "--rematch-only"], cwd=HERE, capture_output=True, text=True, encoding="utf-8", errors="replace")
    print((r.stdout or "")[-1500:], flush=True); rc = r.returncode
else:
    print("새로 들어온 거래 없음 — 단지 다시 잇기 건너뜀", flush=True)
종후 = 종류셈()
종류별 = " · ".join(f"{종류말.get(k, k)} +{종후[k] - 종전.get(k, 0):,}" for k in sorted(종후) if 종후[k] - 종전.get(k, 0) > 0)
cur.execute(f"SELECT MAX(deal_ymd) FROM silver.rtms_trade WHERE deal_ymd >= '{frm}01' AND deal_ymd <= %s", (time.strftime("%Y%m%d"),)); 최근 = cur.fetchone()[0]
print(f"결과: 새로 {새로:,}건 · 해제 표시 {해제:+,}건 · 전체 {후[0]:,} · 최근 계약 {최근}" + (f" · {종류별}" if 종류별 else ""), flush=True)
if 기록:
    cur.execute("UPDATE ops.rtms_fetch_log SET 끝 = %s, 받기초 = %s, 새로 = %s, 해제 = %s, 종류별 = %s, 최근계약 = %s, 실패 = %s, 다시잇기 = %s WHERE id = %s",
                (time.strftime("%Y-%m-%d %H:%M:%S"), 받기초, 새로, 해제, 종류별[:1000] or None, 최근, len(실패), 1 if 새로 > 0 else 0, 기록)); cur.connection.commit()
sys.exit(1 if 실패 or rc != 0 else 0)
