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
# ★ 2026-10-29 전국: 두 번째 인자 'nation' 이면 전국 파일(VM $HOME/sgis/fetch_nation.py 로 받은 것 — 3,559동).
#   서울·안양 457동은 예전 파일과 도형·이름이 **한 점도 다르지 않다**(대조함).
SUF  = '_nation' if len(sys.argv) > 2 and sys.argv[2] == 'nation' else ''
SRC  = os.path.join(HERE, 'data', f'adm_boundary_sgis_{YEAR}{SUF}.geojson')
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

# ★ 2026-10-29 '넓게 볼 때 그림' — 원본 도형(geom · geojson)은 그대로 두고, **화면 그림용 사본**을 따로 둔다.
#   전국을 한 화면에 보면 원본 그대로는 23MB 다. 점을 덜어낸 사본(더글러스-포이커):
#     s1 = 0.0003°(약 30m · 줌 11 의 한 픽셀보다 작다) · s2 = 0.002°(약 200m · 줌 8 의 한 픽셀보다 작다)
#   고리가 4점 아래로 줄면 원본 고리를 쓴다. 이 사본은 그리기에만 쓴다 — 포함 판정·면적·잇기(276)는 원본 geom.
def dp(pts_, tol):
    if len(pts_) < 3: return pts_
    keep = [False] * len(pts_); keep[0] = keep[-1] = True; st = [(0, len(pts_) - 1)]
    while st:
        i, j = st.pop(); (x1, y1), (x2, y2) = pts_[i], pts_[j]; dx, dy = x2 - x1, y2 - y1; L = (dx * dx + dy * dy) ** 0.5
        best, bi = -1.0, -1
        for k in range(i + 1, j):
            x, y = pts_[k]
            d = abs(dy * x - dx * y + x2 * y1 - y2 * x1) / L if L else ((x - x1) ** 2 + (y - y1) ** 2) ** 0.5
            if d > best: best, bi = d, k
        if bi > 0 and best > tol: keep[bi] = True; st += [(i, bi), (bi, j)]
    return [p for p, k in zip(pts_, keep) if k]
def simp(g, tol):
    def r(ring):
        s_ = dp(ring, tol)
        return s_ if len(s_) >= 4 else ring
    if g['type'] == 'Polygon': c = [r(x) for x in g['coordinates']]
    else: c = [[r(x) for x in p] for p in g['coordinates']]
    return json.dumps({'type': g['type'], 'coordinates': c}, ensure_ascii=False)

fc = json.load(io.open(SRC, encoding='utf-8'))
feats = fc['features']
print(f'{os.path.basename(SRC)} — 행정동 {len(feats)}개', flush=True)
e = env()
conn = pymssql.connect(server=e.get('DB_HOST', '127.0.0.1'), port=int(e.get('DB_PORT', 11433)),
                       user=e.get('DB_USER', 'sa'), password=e.get('DB_PASSWORD', ''),
                       database=e.get('DB_NAME', 'Teomoony'), charset='UTF-8', autocommit=False)
cur = conn.cursor()
cur.execute("IF COL_LENGTH('silver.adm_boundary', 'geojson_s1') IS NULL ALTER TABLE silver.adm_boundary ADD geojson_s1 NVARCHAR(MAX) NULL, geojson_s2 NVARCHAR(MAX) NULL")
cur.execute('DELETE FROM silver.adm_boundary WHERE year = %s', (YEAR,))
print(f'  지운 {YEAR}년 행 {cur.rowcount}', flush=True)
n = 0
for f in feats:
    p, g = f['properties'], f['geometry']
    xs, ys = zip(*pts(g['coordinates']))
    emd = p['adm_nm'].split(' ')[-1]
    cur.execute(
        "INSERT INTO silver.adm_boundary (adm_cd_sgis, year, adm_nm, emd_nm, sgg_cd_sgis, geom, geojson, geojson_s1, geojson_s2,"
        " bbox_minx, bbox_miny, bbox_maxx, bbox_maxy, centroid_lat, centroid_lng, src)"
        " VALUES (%s, %s, %s, %s, %s, geometry::STGeomFromText(%s, 4326).MakeValid(), %s, %s, %s,"
        " %s, %s, %s, %s, %s, %s, %s)",
        (p['adm_cd_sgis'], YEAR, p['adm_nm'], emd, p.get('sgg_cd_sgis'), wkt(g), json.dumps(g, ensure_ascii=False), simp(g, 0.0003), simp(g, 0.002),
         min(xs), min(ys), max(xs), max(ys), None, None, p.get('src')))
    n += 1
cur.execute("""UPDATE silver.adm_boundary
                  SET centroid_lat = geom.STCentroid().STY, centroid_lng = geom.STCentroid().STX
                WHERE year = %s AND geom.STIsValid() = 1 AND geom.STCentroid() IS NOT NULL""", (YEAR,))
conn.commit()
cur.execute("SELECT COUNT(*), SUM(CASE WHEN geom.STIsValid()=1 THEN 1 ELSE 0 END), SUM(CASE WHEN centroid_lat IS NULL THEN 1 ELSE 0 END) FROM silver.adm_boundary WHERE year=%s", (YEAR,))
a, b, c = cur.fetchone()
print(f'  넣은 {n} · 표 {a} · 도형 정상 {b} · 중심점 없음 {c}', flush=True)
