# -*- coding: utf-8 -*-
"""applyhome_cron - 수집 일정 '청약공고 · 경쟁률'(daily 05:10) 이 부르는 것 (2026-10-29 전국)
   1) load_applyhome.py --nation — 전국 공고 · 주택형을 다시 받아 주소를 풀고(applyhome_addr) 단지에 잇는다(290 · 296)
   2) 최근 30일 공고가 이어진 단지만 상세 다시 표(svc.detail_dirty)에 — 값은 안 고친다, 다음 발행이 다시 담는다.
   3) 서비스DB 청약 핀 층(apin) 다시."""
import subprocess, sys
PY = sys.executable
r = subprocess.run([PY, "load_applyhome.py", "--nation"])
if r.returncode: sys.exit(r.returncode)
q = ("SELECT DISTINCT l.complex_id FROM gold.applyhome_link l JOIN silver.applyhome_pblanc p ON p.house_manage_no = l.house_manage_no AND p.pblanc_no = l.pblanc_no "
     "WHERE l.complex_id IS NOT NULL AND TRY_CONVERT(date, p.rcrit_pblanc_de) >= DATEADD(day, -30, CAST(GETDATE() AS date))")
r = subprocess.run([PY, "svc_dirty_sql.py", q, "청약 공고(최근 30일)"])
if r.returncode: sys.exit(r.returncode)
sys.exit(subprocess.run([PY, "svc_layers.py", "--only", "apin,apin_cnt"]).returncode)   # 3) 단지에 안 이어진 공고 핀 층
