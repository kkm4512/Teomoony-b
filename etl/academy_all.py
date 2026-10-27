# -*- coding: utf-8 -*-
"""academy_all - 학원 · 교습소 전국(서울 B10 은 이미) — 시도교육청마다 load_academy.py (2026-10-25)"""
import os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
for office in ["C10", "D10", "E10", "F10", "G10", "H10", "I10", "J10", "K10", "M10", "N10", "P10", "Q10", "R10", "S10", "T10"]:
    print(f"$ load_academy.py --office {office}", flush=True)
    r = subprocess.run([sys.executable, os.path.join(HERE, "load_academy.py"), "--office", office], cwd=HERE)
    if r.returncode: print(f"!! {office} 종료코드 {r.returncode}", flush=True)
