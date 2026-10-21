# -*- coding: utf-8 -*-
"""
실거래(RTMS) 를 **구 단위로 병렬** 적재한다  (2026-10-20)

★ 왜 따로 있나: rtms 는 meta.load_target 의 ops 로 **안 돈다.** run_plan 의
  OPS 사전에는 있지만 NEEDS_PERIOD 라 --from/--to 없이는 못 돌아서, 지금껏
  load_rtms.py 를 사람이 직접 불러 왔다. 25 개 구를 손으로 부르긴 번거롭다.

★ 병렬 단위는 **구**다. load_rtms.py 가 안에서 월 x 종목을 돈다.
  서울 25 구 x 2006~현재(약 240 개월) x 10 종목 이라 호출 수가 크다.

★ 실측(2026-10-20): 건축물대장 쪽은 스레드를 10 -> 20 으로 올려도 총량이
  196~218 쪽/분으로 **그대로**였다. 어딘가 고정된 상한이 있다는 뜻이라
  여기서도 스레드를 많이 줄 이유가 없다. 6 부터 보고 로그로 판단한다.

쓰는 법
  py rtms_seoul.py --from 200601 --to 202610 --workers 6
  py rtms_seoul.py --from 200601 --to 202610 --dry-run
"""
import argparse, json, os, subprocess, sys, threading, time
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from teomoony_ingest import db_connect, q            # noqa: E402

lock = threading.Lock()


def ts():
    return time.strftime("%H:%M:%S")


def hms(s):
    s = int(s)
    return f"{s//3600}시간{(s%3600)//60:02d}분" if s >= 3600 else f"{s//60}분{s%60:02d}초"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="ym_from", default="200601")
    ap.add_argument("--to", dest="ym_to", default=time.strftime("%Y%m"))
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--sido", default="11", help="시도 앞 2자리. 11=서울")
    ap.add_argument("--config", default=os.path.join(HERE, "config.json"))
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    cfg = json.load(open(a.config, encoding="utf-8"))
    conn = db_connect(cfg); cur = conn.cursor()
    q(cur, """SELECT DISTINCT sgg_cd, sgg_nm FROM meta.lawd_code
               WHERE sgg_cd LIKE %s AND emd_nm IS NOT NULL AND ri_nm IS NULL
               ORDER BY sgg_cd""", (a.sido + "%",))
    gus = cur.fetchall()
    conn.close()

    n_mon = (int(a.ym_to[:4]) - int(a.ym_from[:4])) * 12 \
            + (int(a.ym_to[4:6]) - int(a.ym_from[4:6])) + 1
    print(f"[{ts()}] 시군구 {len(gus)}곳 · {a.ym_from}~{a.ym_to} ({n_mon}개월) · "
          f"스레드 {a.workers}")
    print(f"  구 x 월 x 종목(10) = 약 {len(gus)*n_mon*10:,} 호출")
    for sgg, nm in gus:
        print(f"    {sgg} {nm}")
    if a.dry_run:
        print("\n(--dry-run 이라 받지 않았습니다)"); return

    t0 = time.time(); done = {"n": 0, "bad": 0}

    def one(g):
        sgg, nm = g
        st = time.time()
        p = subprocess.run(
            [sys.executable, os.path.join(HERE, "load_rtms.py"),
             "--sgg", sgg, "--from", a.ym_from, "--to", a.ym_to],
            cwd=HERE, capture_output=True, text=True,
            encoding="utf-8", errors="replace")
        out = ((p.stdout or "") + (p.stderr or "")).strip().splitlines()
        with lock:
            done["n"] += 1
            ok = p.returncode == 0
            if not ok:
                done["bad"] += 1
            print(f"  [{ts()}] {'OK' if ok else '!!'} [{done['n']}/{len(gus)}] "
                  f"{sgg} {nm}  {hms(time.time()-st)}  (전체 {hms(time.time()-t0)})")
            for ln in out[-4:]:
                print(f"       {ln}")

    with ThreadPoolExecutor(max_workers=a.workers) as ex:
        list(ex.map(one, gus))
    print(f"\n[{ts()}] 끝. {hms(time.time()-t0)} · 실패 {done['bad']}곳")


if __name__ == "__main__":
    main()
