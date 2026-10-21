# -*- coding: utf-8 -*-
"""서울 전체로 남은 주변정보를 한 줄로 받는다 — 뒷줄(-bg) 전용  2026-10-20

  py seoul_rest.py              전부
  py seoul_rest.py --only kinder semas
  py seoul_rest.py --skip building

★ 왜 이 순서인가 — 의존이 있다 (적재기 머리말을 읽어서 확인했다)
    유치원 : **시군구 단위**. 대상은 gold.complex 의 sigungu_cd 에서 뽑는다.
             build 가 25구를 돌았으니 인자 없이 돌리면 25구가 자동으로 잡힌다.
             좌표가 API 에서 직접 오므로 **필지와 무관**하다.
    상권   : 법정동 bbox 를 silver.cadastral_parcel 에서 뽑는다 -> **필지 필요**
    용도지역: 같은 bbox -> **필지 필요**
    건물   : 같은 bbox -> **필지 필요**. 그리고 예전에 사이트를 느리게 만든
             이력이 있어 **맨 뒤**에 둔다.
  이 작업을 뒷줄에 세워 두면 필지(gold-bg)가 끝난 뒤에 돌므로 순서가 지켜진다.

★ 하나가 실패해도 **멈추지 않는다.** 서로 독립된 데이터라, 상권이 죽었다고
  용도지역을 안 받을 이유가 없다. 대신 끝에 무엇이 죽었는지 **반드시 적고**
  종료코드를 1 로 낸다 - 조용히 성공한 척하지 않는다.

★ 출력은 나오는 대로 흘린다. capture_output 으로 받아 뒀다가 끝에 찍으면
  몇 시간 동안 도는지 죽었는지 분간이 안 된다(필지에서 치른 값).
"""
import argparse, os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))

단계 = [
    ("kinder",   "유치원 (시군구 단위 · 필지와 무관)",        ["load_kinder.py"]),
    ("semas",    "상권 점포 (법정동 bbox · 필지 필요)",       ["load_semas.py"]),
    ("landuse",  "용도지역 (법정동 bbox · 필지 필요)",        ["load_landuse.py"]),
    ("building", "건물 외곽선 (법정동 bbox · 필지 필요 · 무겁다)", ["load_building.py"]),
]


def hms(s):
    s = int(s)
    return f"{s//3600}시간{(s%3600)//60:02d}분" if s >= 3600 else f"{s//60}분{s%60:02d}초"


def ts():
    return time.strftime("%H:%M:%S")


def 흘리며(argv):
    p = subprocess.Popen([sys.executable, "-u"] + list(argv), cwd=HERE,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         text=True, encoding="utf-8", errors="replace")
    꼬리 = []
    for ln in p.stdout:
        ln = ln.rstrip()
        print("  " + ln, flush=True)
        꼬리.append(ln)
        if len(꼬리) > 6:
            꼬리.pop(0)
    p.wait()
    return p.returncode == 0, 꼬리


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", help="이 단계만")
    ap.add_argument("--skip", nargs="*", default=[], help="이 단계는 건너뛴다")
    a = ap.parse_args()

    할것 = [s for s in 단계
            if (not a.only or s[0] in a.only) and s[0] not in a.skip]
    if not 할것:
        sys.exit("할 단계가 없습니다")

    print(f"  시작 {time.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"  단계 {len(할것)}개: {', '.join(s[0] for s in 할것)}\n", flush=True)

    결과 = []
    t0 = time.time()
    for i, (이름, 설명, argv) in enumerate(할것, 1):
        print("=" * 64)
        print(f"[{ts()}] ({i}/{len(할것)}) {이름} — {설명}")
        print("=" * 64, flush=True)
        st = time.time()
        ok, 꼬리 = 흘리며(argv)
        걸림 = time.time() - st
        결과.append((이름, ok, 걸림, 꼬리))
        print(f"\n[{ts()}] ({i}/{len(할것)}) {이름} {'OK' if ok else '★ 실패'} — {hms(걸림)}\n",
              flush=True)

    print("=" * 64)
    print(f"끝 — 전체 {hms(time.time()-t0)}")
    print("=" * 64)
    죽음 = []
    for 이름, ok, 걸림, 꼬리 in 결과:
        print(f"  {'OK   ' if ok else '실패 ★'}  {이름:10s} {hms(걸림)}")
        if not ok:
            죽음.append(이름)
            for ln in 꼬리:
                print(f"        | {ln}")
    if 죽음:
        print(f"\n★ 실패한 단계: {', '.join(죽음)}")
        print("  나머지는 돌았습니다. 고친 뒤 --only 로 그 단계만 다시 돌리면 됩니다.")
        sys.exit(1)
    print("\n서울 전체 주변정보가 다 들어왔습니다.")
    print("★ 학구도는 여기 없습니다 — 원본 변환 파일이 135줄뿐이라 별도 작업입니다.")


if __name__ == "__main__":
    main()
