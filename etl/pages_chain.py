# -*- coding: utf-8 -*-
"""
축을 **정한 순서대로** 이어서 받는다  (2026-10-20)

★ 왜 필요한가: 감시기 큐는 파일 이름을 sorted() 로 집는다. 일감을 여러 개
  떨어뜨리면 내가 정한 순서가 아니라 **가나다 순**으로 돈다 - hsprc(18시간)가
  recap(0분)보다 먼저 잡히는 식이다. 그래서 한 일감 안에서 순서를 지킨다.

★ 축마다 끝나면 **구멍 합계**를 그대로 통과시킨다. 중간에 구멍이 나도 멈추지
  않고 다음 축으로 간다 - 구멍은 meta.load_page 에 남으므로 나중에 그 축만
  다시 돌리면 메워진다. 하나 막혔다고 밤새 아무것도 안 하는 게 더 나쁘다.

쓰는 법
  py pages_chain.py --ops recap,atch,title,jijigu,flr,expos
"""
import argparse, os, re, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
ALIAS = {
    "basis":  "getBrBasisOulnInfo",      "title":  "getBrTitleInfo",
    "recap":  "getBrRecapTitleInfo",     "atch":   "getBrAtchJibunInfo",
    "flr":    "getBrFlrOulnInfo",        "expos":  "getBrExposInfo",
    "exar":   "getBrExposPubuseAreaInfo","hsprc":  "getBrHsprcInfo",
    "jijigu": "getBrJijiguInfo",
}


def ts():
    return time.strftime("%H:%M:%S")


def hms(s):
    s = int(s)
    return f"{s//3600}시간{(s%3600)//60:02d}분" if s >= 3600 else f"{s//60}분{s%60:02d}초"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ops", required=True, help="별칭 쉼표 구분. **이 순서대로** 돈다")
    ap.add_argument("--workers", type=int, default=20)
    ap.add_argument("--chunk", type=int, default=120)
    a = ap.parse_args()

    ops = [x.strip() for x in a.ops.split(",") if x.strip()]
    bad = [o for o in ops if o not in ALIAS]
    if bad:
        sys.exit(f"모르는 축: {', '.join(bad)}  (가능: {', '.join(ALIAS)})")

    t0 = time.time()
    요약 = []
    for i, al in enumerate(ops, 1):
        print(f"\n{'='*64}\n[{ts()}] ({i}/{len(ops)}) {al} 시작\n{'='*64}", flush=True)
        st = time.time()
        p = subprocess.run(
            [sys.executable, os.path.join(HERE, "load_pages.py"),
             "--op", ALIAS[al], "--workers", str(a.workers), "--chunk", str(a.chunk)],
            cwd=HERE, capture_output=True, text=True, encoding="utf-8", errors="replace")
        out = (p.stdout or "") + (p.stderr or "")
        print(out, flush=True)
        m = re.search(r'=> 구멍 합계 (\d+)', out)
        구멍 = int(m.group(1)) if m else None
        요약.append((al, time.time() - st, 구멍, p.returncode == 0))
        print(f"[{ts()}] ({i}/{len(ops)}) {al} 끝 — {hms(time.time()-st)}"
              f" · 구멍 {구멍 if 구멍 is not None else '?'}", flush=True)

    print(f"\n{'='*64}\n[{ts()}] 전체 끝 — {hms(time.time()-t0)}\n{'='*64}")
    print(f"{'축':<10}{'걸린 시간':>12}{'구멍':>8}{'결과':>8}")
    나쁨 = []
    for al, sec, 구멍, ok in 요약:
        print(f"{al:<10}{hms(sec):>12}{(str(구멍) if 구멍 is not None else '?'):>8}"
              f"{('OK' if ok else '실패'):>8}")
        if 구멍 or not ok:
            나쁨.append(al)
    if 나쁨:
        print(f"\n★ 다시 봐야 할 축: {', '.join(나쁨)}")
        print("  구멍은 meta.load_page 에 남아 있다 - 그 축만 다시 돌리면 메워진다.")
    else:
        print("\n모든 축 구멍 0.")


if __name__ == "__main__":
    main()
