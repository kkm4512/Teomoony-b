#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""svc_probe - 서비스 경로가 어디서 답하는지(X-Svc) · 몇 ms · 몇 바이트를 찍는다 (2026-10-25)
  py svc_probe.py 103835 518089 1 --kinds detail,history --times 3"""
import sys, time, urllib.request
ids, kinds, times = [], ['detail'], 2
a = sys.argv[1:]
i = 0
while i < len(a):
    if a[i] == '--kinds': kinds = a[i + 1].split(','); i += 2
    elif a[i] == '--times': times = int(a[i + 1]); i += 2
    else: ids.append(a[i]); i += 1
for u0 in [x for x in ids if x.startswith('/')]:   # 경로를 그대로 준 것: 물음표 붙은 지도 요청 등
    for n in range(times):
        t = time.time()
        try:
            r = urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:5173" + u0, headers={'Accept-Encoding': 'gzip'}), timeout=60)
            b = r.read()
            print(f"{int((time.time()-t)*1000):>6}ms {r.status} {r.headers.get('X-Svc') or '-':<6} {len(b):>8}B  {u0}", flush=True)
        except Exception as e:
            print(f"   ERR {e}  {u0}", flush=True)
        time.sleep(0.3)
ids = [x for x in ids if not x.startswith('/')]
for cid in ids:
    for k in kinds:
        u = f"http://127.0.0.1:5173/api/complexes/{cid}" + ("" if k == 'detail' else "/" + k)
        for n in range(times):
            t = time.time()
            try:
                r = urllib.request.urlopen(urllib.request.Request(u, headers={'Accept-Encoding': 'gzip'}), timeout=60)
                b = r.read()
                print(f"{cid:>7} {k:<10} #{n+1} {r.status} {r.headers.get('X-Svc') or '-':<6} {int((time.time()-t)*1000):>5}ms {len(b):>9}B(gz전송)")
            except Exception as e:
                print(f"{cid:>7} {k:<10} #{n+1} ERR {e}")
            time.sleep(0.5)
