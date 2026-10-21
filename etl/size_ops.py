# -*- coding: utf-8 -*-
"""
축별로 **얼마나 되는 일인지** 한 번에 잰다  (2026-10-20)

★ 왜: 서울 25 구를 넣고 나서 "며칠짜리냐" 를 답하려면 축마다 총 쪽수를 알아야
  한다. load_pages.py --dry-run 이 법정동당 1 호출로 totalCount 를 받아 오므로
  그걸 축마다 돌리고 **표로 모은다.**

★ 선행을 조심한다: v_load_plan 은 basis/pms 말고는 **기본개요가 들어간 법정동만**
  계획에 올린다. 기본개요가 아직인 구는 다른 축의 계산에서 **빠진다** - 그래서
  이 표의 숫자는 "지금 열려 있는 만큼" 이고, 기본개요가 끝나야 전체가 보인다.
  그 사실을 표 아래에 적는다. 모르는 것을 아는 척하지 않는다.
"""
import argparse, os, re, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
OPS = [
    ("basis",  "getBrBasisOulnInfo",       "기본개요"),
    ("title",  "getBrTitleInfo",           "표제부"),
    ("recap",  "getBrRecapTitleInfo",      "총괄표제부"),
    ("atch",   "getBrAtchJibunInfo",       "부속지번"),
    ("flr",    "getBrFlrOulnInfo",         "층별개요"),
    ("expos",  "getBrExposInfo",           "전유부"),
    ("exar",   "getBrExposPubuseAreaInfo", "전유공용면적"),
    ("hsprc",  "getBrHsprcInfo",           "주택가격"),
    ("jijigu", "getBrJijiguInfo",          "지역지구"),
]


def ts():
    return time.strftime("%H:%M:%S")


def one(op):
    p = subprocess.run([sys.executable, os.path.join(HERE, "load_pages.py"),
                        "--op", op, "--dry-run"],
                       cwd=HERE, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    out = (p.stdout or "") + (p.stderr or "")
    동, 쪽, 건, 남 = 0, 0, 0, 0
    for ln in out.splitlines():
        m = re.search(r'전체 ([\d,]+)쪽 \(건수 ([\d,]+)\) · 남은 ([\d,]+)쪽', ln)
        if m:
            동 += 1
            쪽 += int(m.group(1).replace(",", ""))
            건 += int(m.group(2).replace(",", ""))
            남 += int(m.group(3).replace(",", ""))
    return 동, 쪽, 건, 남, p.returncode == 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default=None, help="별칭 쉼표 구분. 생략하면 전부")
    ap.add_argument("--rate", type=float, default=270.0,
                    help="쪽/분. 실측 기본값 (hsprc 253, basis 272)")
    a = ap.parse_args()
    고를것 = set(x.strip() for x in a.only.split(",")) if a.only else None

    rows = []
    for al, op, nm in OPS:
        if 고를것 and al not in 고를것:
            continue
        print(f"[{ts()}] {al} ({nm}) 재는 중...", flush=True)
        동, 쪽, 건, 남, ok = one(op)
        rows.append((al, nm, 동, 쪽, 건, 남, ok))
        print(f"           법정동 {동:,} · 전체 {쪽:,}쪽 · 건수 {건:,} · 남은 {남:,}쪽"
              + ("" if ok else "   ** 측정 실패 **"), flush=True)

    print("\n================ 서울 축별 크기 ================")
    print(f"{'축':<14}{'법정동':>7}{'전체쪽':>10}{'건수':>14}{'남은쪽':>10}{'예상':>9}")
    총남 = 0
    for al, nm, 동, 쪽, 건, 남, ok in rows:
        총남 += 남
        분 = 남 / a.rate if a.rate else 0
        때 = f"{분/60:.1f}시간" if 분 >= 60 else f"{분:.0f}분"
        print(f"{nm:<14}{동:>7,}{쪽:>10,}{건:>14,}{남:>10,}{때:>9}")
    총분 = 총남 / a.rate if a.rate else 0
    print("-" * 64)
    print(f"{'합계':<14}{'':>7}{'':>10}{'':>14}{총남:>10,}"
          f"{(str(round(총분/60,1))+'시간'):>9}")
    print(f"\n  기준 속도 {a.rate:.0f}쪽/분 (실측: hsprc 253, basis 272)")
    print("  ★ 이 숫자는 **지금 선행이 열려 있는 만큼**이다. v_load_plan 은")
    print("    basis/pms 말고는 기본개요가 들어간 법정동만 계획에 올린다 —")
    print("    기본개요가 아직인 구는 다른 축에서 빠져 있다. 끝난 뒤 다시 재야")
    print("    전체가 보인다.")


if __name__ == "__main__":
    main()
