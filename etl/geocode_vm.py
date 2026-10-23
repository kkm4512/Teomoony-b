"""VWorld 지오코더(도로명주소 → 점) — VM 에서 돈다 (2026-10-23, 326).
   py geocode_vm.py <물을말.txt> <출력.sql> [초]
   ★ 원문 그대로(정제 주소 · 점). 맞는지 가르는 것은 DB(326: 정제 주소 괄호 앞 = 물은 주소). 키는 찍지 않는다."""
import io, json, os, sys, time, urllib.parse, urllib.request
HERE = os.path.dirname(os.path.abspath(__file__))
E = {}
for line in io.open(os.path.join(HERE, '..', '.env'), encoding='utf-8-sig'):
    line = line.strip()
    if line and not line.startswith('#') and '=' in line:
        k, v = line.split('=', 1); E[k.strip()] = v.strip().strip('"')
KEY = E['VWORLD_KEY']; DOM = E.get('VWORLD_DOMAIN') or 'localhost'
src, out = sys.argv[1], sys.argv[2]; lim = float(sys.argv[3]) if len(sys.argv) > 3 else 160
done = set()
if os.path.exists(out):
    for l in io.open(out, encoding='utf-8'):
        if l.startswith('-- k '): done.add(l[5:].rstrip('\n'))
w = io.open(out, 'a', encoding='utf-8'); t0 = time.time(); n = 0
def q(v): return 'NULL' if v is None else "N'" + str(v).replace("'", "''") + "'"
for kw in [l.rstrip('\n') for l in io.open(src, encoding='utf-8') if l.strip()]:
    if kw in done: continue
    if time.time() - t0 > lim: break
    d = {'service': 'address', 'request': 'getcoord', 'version': '2.0', 'crs': 'epsg:4326', 'address': kw, 'refine': 'true',
         'simple': 'false', 'format': 'json', 'type': 'ROAD', 'key': KEY, 'domain': DOM}
    st = x = y = ref = None
    for k in range(3):
        try:
            r = json.loads(urllib.request.urlopen('https://api.vworld.kr/req/address?' + urllib.parse.urlencode(d), timeout=30).read().decode('utf-8'))['response']
            st = r.get('status'); p = (r.get('result') or {}).get('point') or {}; x, y = p.get('x'), p.get('y'); ref = (r.get('refined') or {}).get('text'); break
        except Exception as ex:
            st = 'ERROR'; time.sleep(2 * (k + 1))
    if st == 'ERROR': continue   # 다음에 다시
    w.write('-- k %s\nIF NOT EXISTS (SELECT 1 FROM silver.vworld_geocode WHERE keyword = %s) INSERT INTO silver.vworld_geocode (keyword, 종류, status, x, y, refined) VALUES (%s, \'ROAD\', %s, %s, %s, %s);\n'
            % (kw, q(kw), q(kw), q(st), x if x else 'NULL', y if y else 'NULL', q(ref)))
    w.flush(); n += 1; time.sleep(0.05)
print('이번', n, '·', round(time.time() - t0), 's')
