# -*- coding: utf-8 -*-
"""
적재한 silver 를 **화면이 읽는 gold 로 만든다**  (2026-10-20)

★ 왜 필요한가
  서울 25구 기본개요 465만 건이 silver 에 들어왔는데 `gold.complex` 는
  **기존 4개 구에만** 있었다(나머지 21개 구 0). 화면은 gold 를 읽으므로
  **지금까지 받은 게 하나도 안 보인다.** load_pages.py 는 적재만 하고
  build 를 안 돌린다 - run_plan.py go 가 하던 일을 내가 떼어 놓은 탓이다.

★ 순서가 강제된다
  build(gold.complex, complex_pnu) -> cadastral(필지) -> 좌표
  load_cadastral.py 는 **gold.complex_pnu 에서** 대상 법정동을 뽑는다.
  build 가 없으면 받을 필지가 없다. 좌표가 없으면 지도에 안 뜬다.

★ 앞줄과 같이 돌려도 되는 이유
  build 가 읽는 것은 기본개요·표제부·총괄·부속지번인데 **그 축들은 이미 끝났다.**
  지금 앞줄이 쓰는 것은 층별·전유부·전유공용·주택가격이고 build 는 안 읽는다.
  (그래도 교착은 날 수 있다 - 그래서 구마다 재시도한다.)
"""
import argparse, json, os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from teomoony_ingest import db_connect, q            # noqa: E402


def ts():
    return time.strftime("%H:%M:%S")


def hms(s):
    s = int(s)
    return f"{s//3600}시간{(s%3600)//60:02d}분" if s >= 3600 else f"{s//60}분{s%60:02d}초"


def run(*argv, label=""):
    p = subprocess.run([sys.executable] + list(argv), cwd=HERE,
                       capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    out = ((p.stdout or "") + (p.stderr or "")).strip().splitlines()
    return p.returncode == 0, out


def run_stream(*argv):
    """★ 나오는 대로 그대로 집는다(2026-10-20).
       capture_output 은 죽은 뒤에야 보여준다. 필지 적쟬는 여러 시간이라
       그 사이 내내 로그가 한 줄도 안 늘어 **도는지 죽었는지 분간이 안 됐다.**
       뒷줄은 사람이 지키지 않으니 로그가 유일한 눈이다 — 가려지 않는다. """
    p = subprocess.Popen([sys.executable, "-u"] + list(argv), cwd=HERE,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         text=True, encoding="utf-8", errors="replace")
    tail = []
    for ln in p.stdout:
        ln = ln.rstrip()
        print("  " + ln, flush=True)
        tail.append(ln)
        if len(tail) > 12:
            tail.pop(0)
    p.wait()
    return p.returncode == 0, tail


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sido", default="11")
    ap.add_argument("--config", default=os.path.join(HERE, "config.json"))
    ap.add_argument("--skip-cadastral", action="store_true")
    ap.add_argument("--retry", type=int, default=3, help="교착이면 구마다 다시")
    a = ap.parse_args()

    cfg = json.load(open(a.config, encoding="utf-8"))
    conn = db_connect(cfg); cur = conn.cursor()
    q(cur, """SELECT DISTINCT t.sgg_cd FROM meta.load_target t
               WHERE t.enabled = 1 AND t.sgg_cd LIKE %s ORDER BY t.sgg_cd""",
      (a.sido + "%",))
    gus = [r[0] for r in cur.fetchall()]
    print(f"[{ts()}] 단지 구성할 시군구 {len(gus)}곳", flush=True)

    t0 = time.time(); 실패 = []
    for i, sgg in enumerate(gus, 1):
        for 번 in range(1, a.retry + 1):
            st = time.time()
            ok, out = run("teomoony_ingest.py", "build", "--sigungu", sgg)
            꼬리 = " / ".join(x.strip() for x in out[-2:] if x.strip())
            print(f"  [{ts()}] {'OK' if ok else '!!'} [{i}/{len(gus)}] {sgg} "
                  f"{hms(time.time()-st)}  {꼬리}", flush=True)
            if ok:
                break
            if 번 < a.retry:
                print(f"       -> {번*5}초 쉬고 다시 ({번}/{a.retry-1})", flush=True)
                time.sleep(번 * 5)
        else:
            실패.append(sgg)

    q(cur, """SELECT 단지 = COUNT(*),
                     좌표 = SUM(CASE WHEN centroid_lat IS NOT NULL THEN 1 ELSE 0 END)
                FROM gold.complex WHERE is_active = 1""")
    단지, 좌표 = cur.fetchone()
    print(f"\n[{ts()}] 단지 구성 끝 — {hms(time.time()-t0)} · 실패 {len(실패)}곳"
          + (f" ({', '.join(실패)})" if 실패 else ""))
    print(f"  gold.complex {단지:,}개 · 좌표 있는 것 {좌표:,}개")
    conn.close()

    if a.skip_cadastral:
        print("  (--skip-cadastral 이라 필지는 받지 않습니다)"); return

    # ---- 필지: 좌표가 여기서 나온다 ----
    print(f"\n[{ts()}] 필지(VWorld) 적재 — 단지가 참조하는 법정동 전부", flush=True)
    st = time.time()
    ok, out = run_stream("load_cadastral.py")
    print(f"[{ts()}] 필지 {'OK' if ok else '실패'} — {hms(time.time()-st)}")
    print("  ★ 좌표는 gold.usp_refresh_complex_geo 가 필지 bbox 로 계산한다 -"
          " 필지가 없으면 단지가 지도에 안 뜬다.")


if __name__ == "__main__":
    main()
