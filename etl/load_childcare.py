# -*- coding: utf-8 -*-
"""load_childcare - 어린이집(보육정보공개 cpmsapi030) 적재  2026-10-22  (deploy/sql/303)

  py load_childcare.py                         서울 25구 + 안양(41170)
  py load_childcare.py --arcode 11290 41170    몇 곳만
  py load_childcare.py --sql-out 파일          DB 대신 SQL 파일(/api/_apply 로)

★ 키 = 환경변수 CHILDCARE_KEY, 없으면 .env CHILDCARE_KEY. 키는 화면·로그에 안 찍는다.
★ 빈칸만 NULL. 0 은 0(이 자료에선 '없음'). 좌표가 없으면 비운다.
★ 시군구 하나를 **다 받은 뒤에만** 그 시군구에서 안 나온 곳을 is_current=0 으로 내린다.
"""
import argparse, io, json, os, sys, time, urllib.parse, urllib.request
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
ENV = os.path.join(HERE, "..", ".env")
URL = "https://api.childcare.go.kr/mediate/rest/cpmsapi030/cpmsapi030/request"
SEOUL = ["11110", "11140", "11170", "11200", "11215", "11230", "11260", "11290", "11305", "11320", "11350", "11380", "11410",
         "11440", "11470", "11500", "11530", "11545", "11560", "11590", "11620", "11650", "11680", "11710", "11740"]
ANYANG = ["41170"]


def env():
    d = {}
    try:
        for line in io.open(ENV, encoding="utf-8-sig"):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1); d[k.strip()] = v.strip().strip('"')
    except FileNotFoundError:
        pass
    return d


def fetch(key, arcode):
    u = URL + "?" + urllib.parse.urlencode({"key": key, "arcode": arcode})
    for t in range(4):
        try:
            with urllib.request.urlopen(u, timeout=90) as r:
                root = ET.fromstring(r.read())
            err = root.findtext("errcode")
            if err: raise RuntimeError(f"{err} {root.findtext('errmsg')}")
            return [{c.tag: (c.text or "").strip() for c in it} for it in root.findall("item")]
        except Exception as ex:
            if t == 3: raise RuntimeError(f"arcode {arcode}: {str(ex).replace(key, '***')[:200]}")
            time.sleep(3 * (t + 1))


def s(v): return v or None
def i(v):
    try: return int(float(v))
    except Exception: return None
def f(v):
    try:
        x = float(v); return x if x else None   # 좌표 0 은 없음
    except Exception: return None
def d(v): return v[:10] if v and len(v) >= 10 else None


COLS = ["stcode", "arcode", "시도", "시군구", "이름", "유형", "상태", "주소", "전화", "홈페이지", "정원", "현원", "보육실수", "보육실면적",
        "놀이터수", "CCTV수", "교직원수", "반수", "통학차량", "제공서비스", "인가일", "휴지시작", "휴지끝", "폐지일", "기준일", "lat", "lng", "raw_json"]


def row(x, arcode):
    return dict(stcode=x.get("stcode"), arcode=arcode, 시도=s(x.get("sidoname")), 시군구=s(x.get("sigunname")), 이름=x.get("crname") or "(이름 없음)",
                유형=s(x.get("crtypename")), 상태=s(x.get("crstatusname")), 주소=s(x.get("craddr")), 전화=s(x.get("crtelno")),
                홈페이지=s(x.get("crhome")), 정원=i(x.get("crcapat")), 현원=i(x.get("crchcnt")), 보육실수=i(x.get("nrtrroomcnt")),
                보육실면적=i(x.get("nrtrroomsize")), 놀이터수=i(x.get("plgrdco")), CCTV수=i(x.get("cctvinstlcnt")), 교직원수=i(x.get("chcrtescnt")),
                반수=i(x.get("CLASS_CNT_TOT")), 통학차량=s(x.get("crcargbname")), 제공서비스=s(x.get("crspec")), 인가일=d(x.get("crcnfmdt")),
                휴지시작=d(x.get("crpausebegindt")), 휴지끝=d(x.get("crpauseenddt")), 폐지일=d(x.get("crabldt")), 기준일=d(x.get("datastdrdt")),
                lat=f(x.get("la")), lng=f(x.get("lo")), raw_json=json.dumps(x, ensure_ascii=False))


def q(v):
    if v is None: return "NULL"
    if isinstance(v, (int, float)): return repr(v)
    return "N'" + str(v).replace("'", "''") + "'"


def sql_for(arcode, rows):
    out = []
    for k in range(0, len(rows), 150):
        vals = ",\n".join("(" + ",".join(q(r[c]) for c in COLS) + ")" for r in rows[k:k + 150])
        out.append(f"MERGE silver.childcare AS t USING (VALUES\n{vals}\n) AS s({', '.join(COLS)}) ON t.stcode = s.stcode\n"
                   f"WHEN MATCHED THEN UPDATE SET {', '.join(f't.{c}=s.{c}' for c in COLS[1:])}, t.is_current=1, t.loaded_at=SYSDATETIME(),\n"
                   f"  t.geog = CASE WHEN s.lat BETWEEN 33 AND 39 AND s.lng BETWEEN 124 AND 132 THEN geography::Point(s.lat, s.lng, 4326) END\n"
                   f"WHEN NOT MATCHED THEN INSERT ({', '.join(COLS)}, geog) VALUES ({', '.join('s.' + c for c in COLS)},\n"
                   f"  CASE WHEN s.lat BETWEEN 33 AND 39 AND s.lng BETWEEN 124 AND 132 THEN geography::Point(s.lat, s.lng, 4326) END);\nGO\n")
    ids = ",".join(q(r["stcode"]) for r in rows)
    out.append(f"UPDATE silver.childcare SET is_current = 0 WHERE arcode = '{arcode}' AND is_current = 1 AND stcode NOT IN ({ids or 'NULL'});\nGO\n")
    return out


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--arcode", nargs="*"); ap.add_argument("--sql-out"); a = ap.parse_args()
    key = os.environ.get("CHILDCARE_KEY") or env().get("CHILDCARE_KEY", "")
    if not key: sys.exit(".env 에 CHILDCARE_KEY 가 없습니다")
    codes = a.arcode or (SEOUL + ANYANG)
    allsql = ["/* load_childcare.py --sql-out (303) */\nSET NOCOUNT ON;\nGO\n"]; 합 = 0; 본 = set()
    conn = None
    if not a.sql_out:
        import pymssql
        e = env()
        conn = pymssql.connect(server=e.get("DB_HOST", "127.0.0.1"), port=int(e.get("DB_PORT", 11433)), user=e.get("DB_USER", "sa"),
                               password=e.get("DB_PASSWORD", ""), database=e.get("DB_NAME", "Teomoony"), charset="UTF-8", autocommit=False)
    for n, ac in enumerate(codes, 1):
        rows = [row(x, ac) for x in fetch(key, ac) if x.get("stcode")]
        겹 = [r["stcode"] for r in rows if r["stcode"] in 본]
        if 겹: print(f"  ! {ac}: 다른 시군구와 겹친 코드 {len(겹)} — 앞선 것을 덮는다", flush=True)
        본.update(r["stcode"] for r in rows); 합 += len(rows)
        print(f"  [{n}/{len(codes)}] {ac} {len(rows):,}곳 · 좌표 없음 {sum(1 for r in rows if r['lat'] is None)}", flush=True)
        st = sql_for(ac, rows)
        if conn:
            cur = conn.cursor()
            for x in st: cur.execute(x.replace("\nGO\n", ""))
            conn.commit()
        else:
            allsql += st
    print(f"합 {합:,}곳", flush=True)
    if a.sql_out:
        io.open(a.sql_out, "w", encoding="utf-8").write("".join(allsql)); print("SQL 파일:", a.sql_out)
    else:
        conn.close()


if __name__ == "__main__":
    main()
