# -*- coding: utf-8 -*-
"""mois_jscode_watch - 행안부 행정동·법정동 코드 변경 게시판을 보고, 새 판이 있으면 받아서 넣고 대응표를 다시 만든다 (2026-10-31)
  python mois_jscode_watch.py            새 판이 있으면 받기 → 넣기(395) → 대응표(396 · 397) → 바뀐 코드 요약
  python mois_jscode_watch.py --check    받지 않고 게시판 최신 판만 알려 준다
  종료코드: 0 새 판 넣음 · 3 새 판 없음(건너뜀)

출처: 행정안전부 누리집 > 업무안내 > 주민등록·인감 > 「행정기관(행정동) 및 관할구역(법정동) 코드 변경내역 알림」(bbsId=BBSMSTR_000000000052)
      글마다 첨부 jscodeYYYYMMDD.zip(현행) · jscodeYYYYMMDD(말소코드포함).zip — 뒤의 것을 받는다. 로그인 없음 · 사람이 누르는 것과 같은 한 번 받기.
★ 이미 넣은 판(ops.mois_jscode_file)보다 새 판일 때만 받는다. 받은 파일은 data/region_code/ 에 그대로 둔다(원본).
★ 통계청 SGIS 행정동 경계는 해마다 나온다 — 우리 경계 연도 다음 해가 나왔는지도 같이 본다(나왔으면 알리기만 · 받기는 따로).
"""
import html, io, os, re, sys, time, urllib.parse, urllib.request
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from svc_publish import env, ms_conn

BASE = "https://www.mois.go.kr"
LIST = BASE + "/frt/bbs/type001/commonSelectBoardList.do?bbsId=BBSMSTR_000000000052"
UA = {"User-Agent": "Mozilla/5.0 (teomoony mois_jscode_watch)"}
DATA = os.path.join(HERE, "..", "data", "region_code")


def 읽기(url, ref=None):
    h = dict(UA)
    if ref: h["Referer"] = ref
    for i in range(3):
        try:
            return urllib.request.urlopen(urllib.request.Request(url, headers=h), timeout=90).read()
        except Exception as e:
            if i == 2: raise
            time.sleep(3 * (i + 1))


def 최신글():
    """게시판 첫 쪽에서 '코드' 가 들어간 글 → 각 글의 첨부 중 말소코드포함 zip. 가장 새 판 하나."""
    s = 읽기(LIST).decode("utf-8", "ignore")
    글 = re.findall(r'nttId=(\d+)"[^>]*>\s*([^<]*관할구역\(법정동\)[^<]*)<', s)
    best = None
    for ntt, 제목 in 글[:6]:
        u = f"{BASE}/frt/bbs/type001/commonSelectBoardArticle.do?bbsId=BBSMSTR_000000000052&nttId={ntt}"
        a = 읽기(u).decode("utf-8", "ignore")
        for href, 이름 in re.findall(r'href="(/cmm/fms/FileDown\.do\?atchFileId=[^"&]+&amp;fileSn=\d+)">\s*(?:<img[^>]*>)?\s*([^<]+?)\s*&nbsp;', a):
            이름 = html.unescape(이름).strip()
            m = re.match(r"jscode(\d{8})\(말소코드포함\)\.zip$", 이름)
            if m and (best is None or m.group(1) > best[0]):
                best = (m.group(1), BASE + html.unescape(href), 이름, u, html.unescape(제목).strip())
    return best


def main():
    e = env(); conn = ms_conn(e); cur = conn.cursor()
    cur.execute("SELECT MAX(판) FROM ops.mois_jscode_file"); 넣은판 = (cur.fetchone() or [None])[0]
    b = 최신글()
    if not b: sys.exit("게시판에서 말소코드포함 첨부를 못 찾음 — 게시판 형식이 바뀌었는지 볼 것")
    판, url, 이름, 글, 제목 = b
    print(f"게시판 최신: {판} · {제목}\n우리 DB: {넣은판 or '없음'}", flush=True)
    if "--check" in sys.argv: return
    if 넣은판 and 판 <= 넣은판:
        print("새 판 없음 — 건너뜀"); 경계연도(cur); sys.exit(3)
    os.makedirs(DATA, exist_ok=True)
    p = os.path.join(DATA, f"jscode{판}_malso.zip")
    raw = 읽기(url, ref=글)
    if raw[:2] != b"PK": sys.exit(f"zip 이 아님({len(raw)}바이트) — 넣지 않음")
    open(p, "wb").write(raw); print(f"받음 {이름} {len(raw):,}바이트 → {p}", flush=True)
    import subprocess
    r = subprocess.run([sys.executable, os.path.join(HERE, "load_mois_jscode.py"), p])
    if r.returncode != 0: sys.exit(f"넣기 실패({r.returncode})")
    # 지난 판과 비교: 새로 생긴 코드 · 새로 말소된 코드
    if 넣은판:
        cur.execute("""SELECT 종류 = CASE WHEN o.법정동코드 IS NULL THEN N'새 코드' ELSE N'말소' END, n.법정동코드,
                              CONCAT(n.시도명, N' ' + n.시군구명, N' ' + n.읍면동명, N' ' + n.동리명), ISNULL(n.말소일자, n.생성일자)
                         FROM silver.mois_bdong_code n
                         LEFT JOIN silver.mois_bdong_code o ON o.판 = %s AND o.법정동코드 = n.법정동코드
                        WHERE n.판 = %s AND (o.법정동코드 IS NULL OR (o.말소일자 IS NULL AND n.말소일자 IS NOT NULL))
                        ORDER BY 1, 2""", (넣은판, 판))
        rows = cur.fetchall()
        print(f"\n법정동 바뀜 {len(rows)}건 (지난 판 {넣은판} → {판})")
        for r in rows[:200]: print("  ", *r)
    cur.execute("EXEC gold.usp_build_bdong_succ"); print("\n옛→새 법정동 확정:", cur.fetchall())
    cur.execute("EXEC gold.usp_build_adm_link"); print("행정동 경계 연결:", cur.fetchall())
    경계연도(cur)


def 경계연도(cur):
    """SGIS 에 우리 경계 다음 해가 나왔나 — 알리기만"""
    try:
        cur.execute("SELECT MAX(year) FROM silver.adm_boundary"); y = int(cur.fetchone()[0])
        e = env(); B = "https://sgisapi.mods.go.kr/OpenAPI3"
        import json
        q = urllib.parse.urlencode({"consumer_key": e["SGIS_KEY"], "consumer_secret": e["SGIS_SECRET"]})
        tok = json.loads(읽기(B + "/auth/authentication.json?" + q))["result"]["accessToken"]
        g = json.loads(읽기(B + "/boundary/hadmarea.geojson?" + urllib.parse.urlencode({"accessToken": tok, "year": str(y + 1), "adm_cd": "11010", "low_search": "1"})))
        if g.get("features"): print(f"★ SGIS 행정동 경계 {y + 1}년판이 나왔습니다 — sgis_fetch_nation.py 로 받을 때입니다(지금 우리 것은 {y}년)")
        else: print(f"SGIS 행정동 경계 {y + 1}년판은 아직 없음(지금 {y}년)")
    except Exception as ex:
        print("SGIS 경계 연도 확인 실패:", type(ex).__name__)


if __name__ == "__main__":
    main()
