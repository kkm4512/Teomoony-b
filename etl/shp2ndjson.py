#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""SHP(EPSG:5186) -> 4326 ndjson 변환  (2026-10-20 etl/ 로 들여옴)

  py shp2ndjson.py <shp경로(확장자 없이)> <출력.ndjson> [시군구코드,쉼표,구분]

★ 왜 저장소 안으로 들였나: 학구도는 **매년 3월·9월** 새로 나온다.
  저장소 밖 임시 스크립트로 두면 다음 사람이 변환법을 복원하지 못한다.
  실제로 그래서 135건(6개 구)만 들어 있는 채로 남아 있었다.

★ 좌표계는 **prj 를 보고** 정한다. 추측하면 한반도 밖으로 날아간다.
  학구도 prj: Korea_2000_Korea_Central_Belt_2010
    (원점 38N/127E · 가산 200000/600000) = EPSG:5186
★ dbf 인코딩은 cpg 가 EUC-KR 이라고 적어 준다.
★ 내려받은 폴더 **안에서 실행하지 말 것** — 파이썬이 그 폴더의 파일을
  모듈로 집어들 수 있다. 여기(etl)에서 절대경로를 주고 돌린다.
"""
import io, json, sys, shapefile
from pyproj import Transformer

base, out = sys.argv[1], sys.argv[2]
only = set(sys.argv[3].split(',')) if len(sys.argv) > 3 and sys.argv[3] else None
tr = Transformer.from_crs("EPSG:5186", "EPSG:4326", always_xy=True)

r = shapefile.Reader(base, encoding="euc-kr")
flds = [f[0] for f in r.fields[1:]]
print("필드:", flds, "· 도형", len(r))


def conv(pts):
    xs, ys = zip(*pts)
    lon, lat = tr.transform(xs, ys)
    return [[round(a, 7), round(b, 7)] for a, b in zip(lon, lat)]


def geom(sh):
    """shapefile 폴리곤은 **파트로만** 나뉜다 - 외곽/구멍 구분이 없다.
       링 방향(시계=외곽, 반시계=구멍)으로 가른다."""
    pts, parts = sh.points, list(sh.parts) + [len(sh.points)]
    polys, cur = [], None
    for i in range(len(parts) - 1):
        ring = pts[parts[i]:parts[i + 1]]
        if len(ring) < 4:
            continue
        area2 = sum((ring[j][0] * ring[j + 1][1] - ring[j + 1][0] * ring[j][1])
                    for j in range(len(ring) - 1))
        ll = conv(ring)
        if area2 < 0:
            cur = [ll]; polys.append(cur)
        elif cur is not None:
            cur.append(ll)
        else:
            cur = [ll]; polys.append(cur)
    if not polys:
        return None
    return ({"type": "Polygon", "coordinates": polys[0]} if len(polys) == 1
            else {"type": "MultiPolygon", "coordinates": polys})


n = skip = 0
with io.open(out, "w", encoding="utf-8") as w:
    for rec, sh in zip(r.records(), r.shapes()):
        d = dict(zip(flds, rec))
        sgg = str(d.get("SGG_CD") or "")
        if only and sgg not in only:
            continue
        g = geom(sh)
        if not g:
            skip += 1
            continue
        w.write(json.dumps({
            "id":   d.get("HAKGUDO_ID"), "nm": d.get("HAKGUDO_NM"),
            "gb":   str(d.get("HAKGUDO_GB") or ""),
            "sd":   str(d.get("SD_CD") or ""), "sgg": sgg,
            "edu":  d.get("EDU_NM"), "base": str(d.get("BASE_DT") or ""),
            "geom": g}, ensure_ascii=False) + "\n")
        n += 1
print(f"쓴 줄 {n:,} · 건너뜀 {skip}")
