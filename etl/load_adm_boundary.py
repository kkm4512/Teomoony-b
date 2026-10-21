# -*- coding: utf-8 -*-
"""행정동 경계(SGIS) 적재 — etl/data/adm_boundary_sgis_<연도>.geojson -> silver.adm_boundary  (2026-10-21)

★ 받기는 VM 에서 했다(SGIS API + pyproj 로 UTM-K -> 4326). 이 PC 의 파이썬에 pyproj 가
  있다고 기대하지 않으려고 **받기와 넣기를 가른다.** 이건 파일 -> DB 만 한다.
★ 그 해(year) 것을 지우고 다시 넣는다 — 파생 표다(원본은 SGIS).
★ 도형은 MakeValid() 로 받는다. 경계 원본에 자기교차가 있으면 STContains 가 틀린다.
"""
import io, json, os, sys
import pymssql

HERE = os.path.dirname(os.path.abspath(__file__))
YEAR = sys.argv[1] if len(sys.argv) > 1 else '2025'
SRC  = os.path.join(HERE, 'data', f'adm_boundary_sgis_{YEAR}.geojson')
ENV  = os.path.join(HERE, '..', '.env')

def env():
    d = {}
    for l in io.open(ENV, encoding='utf-8-sig'):
        l = l.strip()
        if l and not l.startswith('#') and '=' in l:
            k, v = l.split('=', 1); d[k.strip()] = v.strip()
    return d

def ring(r):  return '(' + ', '.join(f'{x} {y}' for x, y in r) + ')'
def poly(p):  return '(' + ', '.join(ring(r) for r in p) + ')'
def wkt(g):
    if g['type'] == 'Polygon':      return 'POLYGON ' + poly(g['coordinates'])
    if g['type'] == 'MultiPolygon': return 'MULTIPOLYGON (' + ', '.join(poly(p) for p in g['coordinates']) + ')'
    raise ValueError(g['type'])
def pts(c):
    if isinstance(c[0], (int, float)): yield c
    else:
        for v in c: yield from pts(v)

fc = json.load(io.open(SRC, encoding='utf-8'))
feats = fc['features']
print(f'{os.path.basename(SRC)} — 행정동 {len(feats)}개', flush=True)
e = env()
conn = pymssql.connect(server=e.get('DB_HOST', '127.0.0.1'), port=int(e.get('DB_PORT', 11433)),
                       user=e.get('DB_USER', 'sa'), password=e.get('DB_PASSWORD', ''),
                       database=e.get('DB_NAME', 'Teomoony'), charset='UTF-8', autocommit=False)
cur = conn.cursor()
cur.execute('DELETE FROM silver.adm_boundary WHERE year = %s', (YEAR,))
print(f'  지운 {YEAR}년 행 {cur.rowcount}', flush=True)
n = 0
for f in feats:
    p, g = f['properties'], f['geometry']
    xs, ys = zip(*pts(g['coordinates']))
    emd = p['adm_nm'].split(' ')[-1]
    cur.execute(
        "INSERT INTO silver.adm_boundary (adm_cd_sgis, year, adm_nm, emd_nm, sgg_cd_sgis, geom, geojson,"
        " bbox_minx, bbox_miny, bbox_maxx, bbox_maxy, centroid_lat, centroid_lng, src)"
        " VALUES (%s, %s, %s, %s, %s, geometry::STGeomFromText(%s, 4326).MakeValid(), %s,"
        " %s, %s, %s, %s, %s, %s, %s)",
        (p['adm_cd_sgis'], YEAR, p['adm_nm'], emd, p.get('sgg_cd_sgis'), wkt(g), json.dumps(g, ensure_ascii=False),
         min(xs), min(ys), max(xs), max(ys), None, None, p.get('src')))
    n += 1
cur.execute("""UPDATE silver.adm_boundary
                  SET centroid_lat = geom.STCentroid().STY, centroid_lng = geom.STCentroid().STX
                WHERE year = %s AND geom.STIsValid() = 1 AND geom.STCentroid() IS NOT NULL""", (YEAR,))
conn.commit()
cur.execute("SELECT COUNT(*), SUM(CASE WHEN geom.STIsValid()=1 THEN 1 ELSE 0 END), SUM(CASE WHEN centroid_lat IS NULL THEN 1 ELSE 0 END) FROM silver.adm_boundary WHERE year=%s", (YEAR,))
a, b, c = cur.fetchone()
print(f'  넣은 {n} · 표 {a} · 도형 정상 {b} · 중심점 없음 {c}', flush=True)
