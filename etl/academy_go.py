# -*- coding: utf-8 -*-
"""학원 한 줄 — DDL 적용 뒤 적재까지  2026-10-20

  뒷줄(academy-bg) 한 자리로 **순서를 보장**한다. 작업 두 개를 큐에 넣으면
  bg_watch 가 이름 가나다 순으로 집어서 'academy-bg' 가 'academy-sql-bg'
  보다 먼저 돈다 — 표가 없는데 적재가 돌아 죽는다. 그래서 하나로 묶는다.

★ 출력은 **나오는 대로 흘린다.** seoul_gold.py 가 capture_output 으로 받아서
  필지 진행이 몇 시간 동안 한 줄도 안 보였던 일을 반복하지 않는다.
"""
import os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))


def hms(s):
    s = int(s); return f"{s//60}분{s%60:02d}초"


def 흘리며(*argv):
    p = subprocess.Popen([sys.executable, "-u"] + list(argv), cwd=HERE,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         text=True, encoding="utf-8", errors="replace")
    for ln in p.stdout:
        print(ln.rstrip(), flush=True)
    p.wait()
    return p.returncode == 0


t0 = time.time()
print("[1/3] 표와 뷰 만들기 (205 · 206 · 207)", flush=True)
if not 흘리며("apply_sql.py", "205_academy.sql", "206_academy_view.sql",
              "207_academy_grp.sql"):
    sys.exit("★ DDL 이 실패했습니다 — 적재는 돌리지 않았습니다.")

print(f"\n[2/4] NEIS 학원 적재 (서울 B10)", flush=True)
if not 흘리며("load_academy.py"):
    sys.exit("★ 적재가 실패했습니다.")

# ★ 2026-10-20: 사용자가 경기 안양(41171 만안 · 41173 동안)을 일부러 범위에
#   넣었고 "거기에도 다 있어야 한다" 고 했다. 안양 학원은 **경기도교육청(J10)**
#   소관이라 서울(B10)만 받으면 0 건이다.
#   NEIS 는 시군구 인자를 받지 않는다 - 교육청 단위로만 준다. 그래서 J10 을
#   받되 **넣기 전에** 행정구역명으로 안양만 거른다(--only-zone). 경기 전체를
#   넣으면 다음 단계인 지오코딩이 수만 건 늘어나는데, 우리가 화면에 쓸 범위는
#   안양 두 구뿐이다.
print(f"\n[3/4] NEIS 학원 적재 (경기 J10 — 안양만 거른다)", flush=True)
if not 흘리며("load_academy.py", "--office", "J10", "--only-zone", "안양"):
    sys.exit("★ 경기(안양) 적재가 실패했습니다 — 서울분은 그대로 남아 있습니다.")

print(f"\n[4/4] 좌표 붙이기 (VWorld 지오코더 — 서울 + 안양)", flush=True)
# ★ 이 단계는 VWORLD_KEY 를 쓴다. 필지 적재와 **같은 키**라 둘이 같이 돌면
#   일일 한도를 다툰다. academy-bg 는 필지가 끝난 뒤에 돌도록 뒷줄에
#   세워 뒀으므로(뒷줄은 한 번에 하나) 여기서는 다툴 상대가 없다.
if not 흘리며("geocode_academy.py"):
    sys.exit("★ 지오코딩이 실패했습니다 — 적재한 25,512건은 그대로 남아 있습니다.\n"
             "  고친 뒤 py geocode_academy.py --retry-fail 로 이어갑니다.")

print(f"\n끝 — {hms(time.time()-t0)}")
print("★ 좌표가 붙은 학원만 gold.v_complex_academy 에 나옵니다.")
print("  못 붙은 수는 gold.v_academy_gap 으로 화면에 같이 적어야 합니다.")
