"""11-19 원천이 같은 줄을 여러 번 주나(읽기만): 묶음 하나를 두 번 받아 줄 수 · 똑같은 줄 개수 분포 · 페이지 수"""
import sys, os, collections, json, time
sys.path.insert(0, os.path.dirname(__file__))
from load_rtms import KINDS, ENV, fetch, load_env, 줄순서
key = load_env(ENV)["DATA_GO_KR_KEY"].strip()
for kind, sgg, ym in [("OFFI_TRADE", "11110", "202502"), ("OFFI_TRADE", "11200", "202503"), ("APT_TRADE_DEV", "11710", "202609")]:
    for t in range(2):
        rows, st = fetch(KINDS[kind][0], key, sgg, ym)
        c = collections.Counter(줄순서(r) for r in rows)
        print(kind, sgg, ym, f"#{t+1}", st, "줄", len(rows), "서로다른줄", len(c), "겹침분포", dict(collections.Counter(c.values())))
        time.sleep(1)
