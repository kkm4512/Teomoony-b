# -*- coding: utf-8 -*-
"""kapt_cost_monthly - 매달 관리비(K-apt 31 오퍼레이션) 한 달치를 전국으로 받는다  2026-10-31 (사장님 "ㅇㅋ" — 관리비 수집 일정 켜기)

  py kapt_cost_monthly.py            이번 달 기준 두 달 전(M-2) 한 달만. 이미 받았으면 건너뜀(종료코드 3)
  py kapt_cost_monthly.py --check    받을 달 · 받은 단지 수만 보고 끝(아무것도 안 받음)
  py kapt_cost_monthly.py --ym 202610   그 달을 억지로

★ 왜 두 달 전인가: 관리비는 '다음 달 말일까지' 올린다(공동주택관리법 시행령 23조 8항). 일정은 매달 3일 04:00 —
  그때 다 올라온 마지막 달이 M-2 다(11월 3일 → 9월분은 10월 31일까지 올라옴 · 10월분은 11월 30일까지라 아직 덜 옴).
★ 이미 받은 달이면 받지 않는다: 그 달 단지 수가 최근 12달 가운데 가장 많이 받은 달의 95% 이상이면 '건너뜀'(3).
  (바로 앞 달과 견주면 둘 다 일부 지역만 받은 달일 때 '다 받음' 으로 잘못 본다 — 10-31 시험에서 202608 · 202607 이 그랬다.) 전국 한 달 = 약 2만 단지 · 15시간.
★ 단지 목록은 이미 받은 K-apt 단지 표(silver.kapt_complex · 주간 갱신)에서(--db-list) — 목록 API 하루 한도를 쓰지 않는다.
★ 종료코드: 0 받음 · 3 건너뜀(이미 받음) · 4 data.go.kr 하루 한도(받은 데까지 두고 멈춤 — 다음 달 같은 명령이 빈 것만 채운다) · 그 밖 실패.
"""
import argparse, os, subprocess, sys
from datetime import date
import pymssql

HERE = os.path.dirname(os.path.abspath(__file__))


def env():
    p = os.path.join(HERE, "..", ".env"); d = {}
    for ln in open(p, encoding="utf-8"):
        ln = ln.strip()
        if ln and not ln.startswith("#") and "=" in ln:
            k, v = ln.split("=", 1); d[k.strip()] = v.strip().strip('"').strip("'")
    return d


def 달빼기(y, m, n):
    m -= n
    while m <= 0: y, m = y - 1, m + 12
    return y, m


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ym")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--rps", default="10")
    a = ap.parse_args()
    t = date.today()
    y, m = 달빼기(t.year, t.month, 2)
    ym = a.ym or f"{y:04d}{m:02d}"
    by, bm = 달빼기(int(ym[:4]), int(ym[4:]), 12); 일년전 = f"{by:04d}{bm:02d}"
    e = env()
    conn = pymssql.connect(server=e.get("DB_HOST", "127.0.0.1"), port=int(e.get("DB_PORT", 11433)), user=e.get("DB_USER", "sa"),
                           password=e.get("DB_PASSWORD", ""), database=e.get("DB_NAME", "Teomoony"), charset="UTF-8")
    cur = conn.cursor()
    cur.execute("SELECT ym, COUNT(DISTINCT kapt_code) FROM silver.kapt_cost WITH (NOLOCK) WHERE ym > %s AND ym <= %s GROUP BY ym", (일년전, ym))
    수 = {r[0]: r[1] for r in cur.fetchall()}
    cur.execute("SELECT DISTINCT LEFT(bjd_code, 5) FROM silver.kapt_complex WITH (NOLOCK) WHERE is_current = 1 AND bjd_code IS NOT NULL")
    시군구 = sorted(r[0] for r in cur.fetchall() if r[0] and len(r[0]) == 5)
    conn.close()
    이번 = 수.get(ym, 0)
    가장 = max(수.items(), key=lambda kv: kv[1]) if 수 else (None, 0)
    앞 = 가장[1]
    print(f"관리비 매달 — 받을 달 {ym} · 그 달 받은 단지 {이번:,} · 최근 12달 가장 많이 받은 달 {가장[0]} {앞:,} · 시군구 {len(시군구)}", flush=True)
    print("  달별: " + " ".join(f"{k}:{v:,}" for k, v in sorted(수.items())), flush=True)
    if 앞 and 이번 >= 앞 * 0.95 and not a.ym:
        print("  이미 받았습니다 — 건너뜀", flush=True); sys.exit(3)
    if a.check:
        print("  (--check: 받지 않고 끝)", flush=True); sys.exit(0)
    cmd = [sys.executable, os.path.join(HERE, "load_kapt_cost.py"), "--db-list", "--ym", ym, "--rps", a.rps]
    for s in 시군구: cmd += ["--sgg", s]
    print(f"  load_kapt_cost.py --db-list --ym {ym} --rps {a.rps} · 시군구 {len(시군구)}", flush=True)
    rc = subprocess.call(cmd, cwd=HERE)
    sys.exit(rc)


if __name__ == "__main__":
    main()
