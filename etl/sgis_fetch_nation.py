# SGIS 행정동 경계 받기 — 전국(2026-10-29). ★ 원격 VM(device_bash)에서 돌린다(pyproj 필요 · 키는 .env 에서만 읽고 안 찍는다). 넣기는 load_adm_boundary.py 2025 nation.
import io, json, os, urllib.request, urllib.parse, time
T0 = time.time()
from pyproj import Transformer
env = {}
for l in io.open(os.path.expanduser('~/mnt/Teomoony/.env'), encoding='utf-8-sig'):
    l = l.strip()
    if l and not l.startswith('#') and '=' in l:
        k, v = l.split('=', 1); env[k.strip()] = v.strip()
B = 'https://sgisapi.mods.go.kr/OpenAPI3'
def get(path, **q):
    u = B + path + '?' + urllib.parse.urlencode(q)
    for i in range(3):
        try:
            with urllib.request.urlopen(u, timeout=90) as r:
                return json.loads(r.read().decode('utf-8'))
        except Exception as e:
            if i == 2: raise
            time.sleep(2)
tok = get('/auth/authentication.json', consumer_key=env['SGIS_KEY'], consumer_secret=env['SGIS_SECRET'])['result']['accessToken']
YEAR = '2025'
# ★ 2026-10-29 전국: 시도 → 시군구 → 시군구마다 행정동(low_search=1). 일반구가 있는 시는 SGIS 가 구 단위로 준다.
sido = [(x['cd'], x['addr_name']) for x in get('/addr/stage.json', accessToken=tok)['result']]
print('시도', len(sido), flush=True)
targets = []
for scd, snm in sido:
    targets += [(x['cd'], x['addr_name']) for x in get('/addr/stage.json', accessToken=tok, cd=scd)['result']]
    time.sleep(0.2)
print('시군구', len(targets), flush=True)
T = Transformer.from_crs('EPSG:5179', 'EPSG:4326', always_xy=True)
def conv(c):
    if isinstance(c[0], (int, float)):
        x, y = T.transform(c[0], c[1]); return [round(x, 7), round(y, 7)]
    return [conv(v) for v in c]
feats = []; per = {}
for cd, nm in targets:
    cp = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'cache', f'{YEAR}_{cd}.json')
    if os.path.exists(cp): g = json.load(open(cp, encoding='utf-8'))
    else:
        if time.time() - T0 > 150: print('  시간 다 됨 — 다시 돌리면 이어 받음', len(per), '/', len(targets), flush=True); raise SystemExit(2)
        g = get('/boundary/hadmarea.geojson', accessToken=tok, year=YEAR, adm_cd=cd, low_search='1')
        if str(g.get('errCd')) == '0': json.dump(g, open(cp, 'w', encoding='utf-8'), ensure_ascii=False)
        time.sleep(0.3)
    if str(g.get('errCd')) != '0':
        print('  실패', cd, nm, g.get('errCd'), g.get('errMsg')); continue
    fs = g.get('features') or []
    per[cd] = len(fs)
    for f in fs:
        p = f['properties']
        feats.append({'type': 'Feature',
            'properties': {'adm_cd_sgis': p['adm_cd'], 'adm_nm': p['adm_nm'], 'sgg_cd_sgis': cd,
                           'year': YEAR, 'src': 'SGIS OpenAPI3 boundary/hadmarea'},
            'geometry': {'type': f['geometry']['type'], 'coordinates': conv(f['geometry']['coordinates'])}})
    if len(per) % 20 == 0: print('  ', len(per), '/', len(targets), len(feats), flush=True)
xs = []; ys = []
def walk(c):
    if isinstance(c[0], (int, float)): xs.append(c[0]); ys.append(c[1])
    else:
        for v in c: walk(v)
for f in feats: walk(f['geometry']['coordinates'])
print('구별', per)
print('행정동', len(feats), '중복코드', len(feats) - len({f['properties']['adm_cd_sgis'] for f in feats}))
print('좌표 범위', min(xs), min(ys), max(xs), max(ys))
print('도형 종류', {t: sum(1 for f in feats if f['geometry']['type'] == t) for t in {f['geometry']['type'] for f in feats}})
out = os.path.expanduser(f'~/mnt/Teomoony/etl/data/adm_boundary_sgis_{YEAR}_nation.geojson')
io.open(out, 'w', encoding='utf-8').write(json.dumps({'type': 'FeatureCollection', 'features': feats}, ensure_ascii=False))
print('저장', out, os.path.getsize(out))
