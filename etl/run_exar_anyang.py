# -*- coding: utf-8 -*-
"""안양 3개 동 전유공용면적(getBrExposPubuseAreaInfo) — 중간에 끊긴 것을 페이지 단위로 마저 받기 (2026-10-22)
   go-rest 에서 박달동 4,300/55,671 · 평촌동 3,400/150,175 · 비산동 8,500/217,622 에서 PARTIAL.
   원인: 6개 동을 동시에 받는 동안 '서비스 연결실패(05)' · 빈 쪽이 겹쳐 재시도 4번을 다 쓰고 멈춤(제공처 쪽 일시 장애).
   → load_pages(쪽 단위 · 빈 쪽은 그 쪽만 비움으로 적고 계속 · 끝나면 빠진 쪽 셈)로 받는다. 이미 받은 쪽은 건너뛴다."""
import subprocess, sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
rc = 0
for sgg, bjd in [("41171", "10300"), ("41173", "10300"), ("41173", "10100")]:
    print(f"=== {sgg}/{bjd} 전유공용면적", flush=True)
    r = subprocess.run([sys.executable, os.path.join(HERE, "load_pages.py"), "--op", "getBrExposPubuseAreaInfo",
                        "--sgg", sgg, "--bjdong", bjd, "--workers", "3"])
    rc = rc or r.returncode
sys.exit(rc)
