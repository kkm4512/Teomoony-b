# -*- coding: utf-8 -*-
"""hub_go - 허브 대장 마무리를 한 번에(사람 없이 이어 가게) (2026-10-27)
  1) 주택가격 '하나뿐' 색인 정리(hub_swap_fixuq) 2) 줄 수 · 색인 대조(hub_swap check) 3) 바꿔 끼우기(hub_swap swap · _api 남김)
  4) 354(단지 구성에서 root UPDATE 뺌) 5) 전국 단지 구성(gold_nation)
  ★ 한 단계라도 실패하면 거기서 멈춘다(다음 단계로 넘어가지 않는다). 되돌리기: py hub_swap.py back"""
import os, subprocess, sys, time
HERE = os.path.dirname(os.path.abspath(__file__)); py = sys.executable
def step(name, *a):
    print(f"\n[{time.strftime('%H:%M:%S')}] ── {name}: {' '.join(a)}", flush=True)
    rc = subprocess.call([py, *a], cwd=HERE)
    if rc != 0: sys.exit(f"[{time.strftime('%H:%M:%S')}] ✘ {name} 실패(종료코드 {rc}) — 여기서 멈춤")
skip = set(sys.argv[1:])
if "fix" not in skip: step("주택가격 색인 정리", "hub_swap_fixuq.py", "bld_hsprc")
step("대조", "hub_swap.py", "check")
if "swap" not in skip: step("바꿔 끼우기", "hub_swap.py", "swap")
step("354 적용", "ms_q.py", os.path.join("..", "deploy", "sql", "354_build_no_root_update.sql"))
step("전국 단지 구성", "gold_nation.py")
print(f"\n[{time.strftime('%H:%M:%S')}] 허브 마무리 끝", flush=True)
