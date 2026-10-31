# -*- coding: utf-8 -*-
"""export_sbx - 클라우드 시험 공간(sandbox)으로 옮길 기준 자료를 파일로 꺼낸다 (2026-10-31 사장님 "다 옮겨")
  py export_sbx.py            → etl/_export/sbx/<이름>.tsv + <이름>.cols.json   (기준 표 + 자료별 코드 쓰임)
  py export_sbx.py --old      → 지금 코드가 아닌(사전 현행에 없는) 법정동 코드를 든 원본 줄 전부(old.*)
  py export_sbx.py --parcels  → 지금 필지 PNU 전부(시도별 parcel_<시도>.tsv) — 옛 코드 줄을 지번으로 지금 코드에 잇는 데 쓴다
★ 읽기만 한다(READ UNCOMMITTED). 원본은 건드리지 않는다.
★ TSV: 탭 구분 · 첫 줄 칸 이름 · NULL = \\N · 값 안의 \\ 탭 줄바꿈은 \\\\ \\t \\n 으로 바꿔 적는다(되돌릴 수 있게).
"""
import json, os, sys, time, datetime, decimal
from svc_publish import env, ms_conn
HERE = os.path.dirname(os.path.abspath(__file__)); OUT = os.path.join(HERE, "_export", "sbx"); os.makedirs(OUT, exist_ok=True)

표 = [  # (이름, 표, 뺄 칸)
    ("meta.lawd_code", "meta.lawd_code", []),
    ("meta.coverage", "meta.coverage", []),
    ("silver.region_link", "silver.region_link", []),
    ("gold.region_hdong", "gold.region_hdong", []),
    ("gold.region_bdong", "gold.region_bdong", []),
    ("gold.region_hdong_change", "gold.region_hdong_change", []),
    ("gold.region_bdong_change", "gold.region_bdong_change", []),
    ("silver.adm_boundary", "silver.adm_boundary", ["geojson", "geojson_s1", "geojson_s2"]),
    ("silver.lawd_boundary", "silver.lawd_boundary", ["geojson"]),
]
쓰임 = [  # 자료마다 들고 있는 지역 코드와 줄 수 — 원본 칸 그대로
    ("use.complex", "SELECT sigungu_cd, bjdong_cd, is_active, n = COUNT_BIG(*), hhld = SUM(CAST(hhld_cnt_sum AS BIGINT)) FROM gold.complex GROUP BY sigungu_cd, bjdong_cd, is_active"),
    ("use.rtms", "SELECT sgg_cd, umd_cd, umd_nm, n = COUNT_BIG(*) FROM silver.rtms_trade GROUP BY sgg_cd, umd_cd, umd_nm"),
    ("use.bld_title", "SELECT sigungu_cd, bjdong_cd, is_current, n = COUNT_BIG(*) FROM silver.bld_title GROUP BY sigungu_cd, bjdong_cd, is_current"),
    ("use.arch_permit", "SELECT sigungu_cd, bjdong_cd, n = COUNT_BIG(*) FROM silver.arch_permit GROUP BY sigungu_cd, bjdong_cd"),
    ("use.kapt", "SELECT bjd_code, n = COUNT_BIG(*) FROM silver.kapt_complex GROUP BY bjd_code"),
    ("use.semas", "SELECT signgu_cd, ldong_cd, ldong_nm, adong_cd, adong_nm, n = COUNT_BIG(*) FROM silver.semas_store GROUP BY signgu_cd, ldong_cd, ldong_nm, adong_cd, adong_nm"),
    ("use.parcel", "SELECT lawd_cd, n = COUNT_BIG(*) FROM silver.cadastral_parcel GROUP BY lawd_cd"),
    ("use.applyhome", "SELECT lawd_cd, 주소_sgg_cd, n = COUNT_BIG(*) FROM silver.applyhome_pblanc GROUP BY lawd_cd, 주소_sgg_cd"),
    ("use.pre_complex", "SELECT 법정동 = LEFT(pnu, 10), 종류, 상태, n = COUNT_BIG(*) FROM gold.pre_complex GROUP BY LEFT(pnu, 10), 종류, 상태"),
    ("use.kindergarten", "SELECT sgg_cd, n = COUNT_BIG(*) FROM silver.kindergarten GROUP BY sgg_cd"),
    ("use.school_zone", "SELECT sgg_cd, n = COUNT_BIG(*) FROM silver.school_zone GROUP BY sgg_cd"),
    ("use.bld_closed_title", "SELECT sigungu_cd, bjdong_cd, n = COUNT_BIG(*) FROM silver.bld_closed_title GROUP BY sigungu_cd, bjdong_cd"),
]

def 칸(v):
    if v is None: return "\\N"
    if isinstance(v, (bytes, bytearray)): return "0x" + v.hex()
    if isinstance(v, (datetime.datetime, datetime.date, datetime.time)): return v.isoformat(sep=" ") if isinstance(v, datetime.datetime) else v.isoformat()
    if isinstance(v, bool): return "1" if v else "0"
    return str(v).replace("\\", "\\\\").replace("\t", "\\t").replace("\n", "\\n").replace("\r", "\\r")

def 꺼내기(cur, 이름, q):
    t0 = time.time(); cur.execute("SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; " + q)
    cols = [d[0] for d in cur.description]; n = 0
    with open(os.path.join(OUT, 이름 + ".tsv"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\t".join(cols) + "\n")
        while True:
            rows = cur.fetchmany(20000)
            if not rows: break
            f.write("".join("\t".join(칸(v) for v in r) + "\n" for r in rows)); n += len(rows)
    print(f"  {이름}: {n:,}줄 · {time.time()-t0:.0f}초", flush=True); return n

옛줄 = [  # 지금 법정동 코드가 아닌 줄 — 원본 칸 전부
    ("old.complex", "gold.complex", "sigungu_cd + bjdong_cd"),
    ("old.bld_title", "silver.bld_title", "sigungu_cd + bjdong_cd"),
    ("old.bld_closed_title", "silver.bld_closed_title", "sigungu_cd + bjdong_cd"),
    ("old.arch_permit", "silver.arch_permit", "sigungu_cd + bjdong_cd"),
    ("old.kapt_complex", "silver.kapt_complex", "bjd_code"),
    ("old.semas_store", "silver.semas_store", "ldong_cd"),
]


def 옛():
    e = env(); cur = ms_conn(e).cursor(); 목록 = {}
    for 이름, t, 식 in 옛줄:
        cur.execute("""SELECT c.name FROM sys.columns c JOIN sys.types ty ON ty.user_type_id = c.user_type_id
                        WHERE c.object_id = OBJECT_ID(%s) AND ty.name NOT IN ('geography', 'geometry') ORDER BY c.column_id""", (t,))
        sel = ", ".join("[" + r[0] + "]" for r in cur.fetchall())
        목록[이름] = 꺼내기(cur, 이름, f"SELECT {sel} FROM {t} x WHERE NOT EXISTS (SELECT 1 FROM meta.lawd_code l WHERE l.lawd_cd = x.{식.replace(' + ', ' + x.')} AND l.is_abolished = 0)")
    json.dump(dict(만든때=datetime.datetime.now().isoformat(timespec="seconds"), 줄=목록), open(os.path.join(OUT, "_manifest_old.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)


def 필지():
    e = env(); cur = ms_conn(e).cursor(); 목록 = {}
    cur.execute("SELECT DISTINCT LEFT(lawd_cd, 2) FROM silver.cadastral_parcel"); 시도들 = sorted(r[0] for r in cur.fetchall() if r[0])
    for sd in 시도들:
        목록[sd] = 꺼내기(cur, f"parcel_{sd}", f"SELECT pnu FROM silver.cadastral_parcel WHERE lawd_cd LIKE '{sd}%' AND is_current = 1")
    json.dump(dict(만든때=datetime.datetime.now().isoformat(timespec="seconds"), 줄=목록), open(os.path.join(OUT, "_manifest_parcel.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)


def main():
    if "--old" in sys.argv: return 옛()
    if "--parcels" in sys.argv: return 필지()
    e = env(); cur = ms_conn(e).cursor(); 목록 = {}
    for 이름, t, 뺌 in 표:
        cur.execute("""SELECT c.name, ty.name, c.max_length, c.precision, c.scale, c.is_nullable, c.collation_name
                         FROM sys.columns c JOIN sys.types ty ON ty.user_type_id = c.user_type_id
                        WHERE c.object_id = OBJECT_ID(%s) ORDER BY c.column_id""", (t,))
        cs = [dict(name=a, type=b, max_length=c, precision=d, scale=s, nullable=bool(nl), collation=co) for a, b, c, d, s, nl, co in cur.fetchall() if a not in 뺌]
        cur.execute("""SELECT c.name FROM sys.indexes i JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
                         JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
                        WHERE i.object_id = OBJECT_ID(%s) AND i.is_primary_key = 1 ORDER BY ic.key_ordinal""", (t,))
        pk = [r[0] for r in cur.fetchall()]
        json.dump(dict(table=t, columns=cs, pk=pk), open(os.path.join(OUT, 이름 + ".cols.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        sel = ", ".join("[" + c["name"] + "]" for c in cs)
        목록[이름] = 꺼내기(cur, 이름, f"SELECT {sel} FROM {t}")
    for 이름, q in 쓰임:
        목록[이름] = 꺼내기(cur, 이름, q)
    json.dump(dict(만든때=datetime.datetime.now().isoformat(timespec="seconds"), 줄=목록), open(os.path.join(OUT, "_manifest.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("끝", OUT)

if __name__ == "__main__":
    main()
