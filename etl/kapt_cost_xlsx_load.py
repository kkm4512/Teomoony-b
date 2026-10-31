# -*- coding: utf-8 -*-
"""kapt_cost_xlsx_load - K-apt 자료실 '관리비공개의무단지 관리비정보' 연도별 엑셀을 받아 silver.kapt_cost_xlsx 에 얹는다  2026-10-31 (사장님 "ㄱㄱ")

  py kapt_cost_xlsx_load.py                 자료실의 연도별 글을 찾아 새 파일만 받고 · 아직 안 넣은 파일만 넣는다(매주 이것)
  py kapt_cost_xlsx_load.py --years 2025 2026
  py kapt_cost_xlsx_load.py --no-fetch      받아 둔 파일만 넣기

★ 받기: 자료실 목록 → 글 보기 → 첨부 목록 → 첨부 받기(사람이 누르는 순서 그대로 · kapt_xlsx_get.py 와 같은 길). 화면을 긁지 않는다.
★ 넣기: 엑셀(xlsx = zip 안 XML)을 한 줄씩 읽어 탭 구분 UTF-16 글로 → DB 안 BULK INSERT(받침표) → MERGE(새로 · 바뀜만). 칸은 머리 이름으로 맞춘다.
  모르는 칸이 있으면 멈춘다(지어서 넣지 않는다). 값은 글자 그대로 받침표에 두고, 숫자 칸만 숫자로 바꿔 넣는다.
★ 종료코드: 0 넣음 · 3 새 파일 없음 · 1 실패.
"""
import argparse, json, os, re, sys, time, zipfile
import xml.etree.ElementTree as ET
import pymssql, requests

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "data", "kapt_cost_xlsx")
XDIR = os.path.join(HERE, "..", "deploy", "bulk", "kapt", "_x")
BASE = "https://www.k-apt.go.kr"
COLS = json.load(open(os.path.join(HERE, "kapt_cost_xlsx_cols.json"), encoding="utf-8"))
NUM = COLS[7:]
NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"


def env():
    d = {}
    for ln in open(os.path.join(HERE, "..", ".env"), encoding="utf-8-sig"):
        ln = ln.strip()
        if ln and not ln.startswith("#") and "=" in ln:
            k, v = ln.split("=", 1); d[k.strip()] = v.strip().strip('"').strip("'")
    return d


# ---------------- 받기 ----------------
def 토큰(h):
    m = re.search(r'<meta\s+name="_csrf"\s+content="([^"]+)"', h) or re.search(r'name="_csrf"\s+value="([^"]+)"', h)
    return m.group(1) if m else ""


def 연도글(s, years):
    l = s.get(f"{BASE}/web/board/webReference/boardList.do", timeout=60); csrf = 토큰(l.text)
    글 = {}
    for page in range(1, 4):
        # 목록은 화면이 boardListAjax.do 로 따로 받는다(분류 03 = 관리비정보)
        r = s.post(f"{BASE}/web/board/webReference/boardListAjax.do", data={"scode": "03", "boardType": "03", "pageNo": str(page),
                   "stype": "", "keyword": "", "_csrf": csrf}, headers={"Referer": l.url, "X-Requested-With": "XMLHttpRequest"}, timeout=60)
        for seq, yy in re.findall(r"goCheck\(\s*(\d+)\s*,\s*0\s*\)[^<]{0,40}(?:<[^>]*>[^<]{0,40}){0,6}?관리비공개의무단지 관리비정보\((\d{4})년\)", r.text):
            글.setdefault(yy, seq)
        if page == 1 and not 글:
            open(os.path.join(XDIR, "_list.html"), "w", encoding="utf-8").write(r.text)   # 모양이 바뀌었으면 보려고
    return {y: 글[y] for y in sorted(글) if not years or y in years}


def 받기(s, seq):
    l = s.get(f"{BASE}/web/board/webReference/boardList.do", timeout=60); csrf = 토큰(l.text)
    v = s.post(f"{BASE}/web/board/webReference/boardView.do", data={"seq": seq, "boardSecret": "0", "boardType": "03", "pageNo": "1", "keyword": "",
               "board_pwd": "", "scodeT": "03", "_csrf": csrf}, headers={"Referer": l.url}, timeout=60)
    csrf = 토큰(v.text) or csrf
    form = {"boardType": "03", "pageNo": "1", "stype": "", "keyword": "", "seq": seq, "scode": "03", "boardPwd": "", "_csrf": csrf}
    r = s.post(f"{BASE}/web/board/webReference/fileListData.do?seq=BOARD_FILE", json=form,
               headers={"X-CSRF-TOKEN": csrf, "Referer": v.url, "Accept": "application/json, */*"}, timeout=60)
    out = []
    for f in (r.json().get("data") or []):
        name = f.get("fileName"); dst = os.path.join(OUT, name)
        if not name or not name.lower().endswith(".xlsx"): continue
        if not os.path.exists(dst):
            d = s.get(f"{BASE}/cmm/file/BOARD/fileDownload.do", params={"key": f.get("seq"), "fileName": name}, headers={"Referer": v.url}, timeout=900, stream=True)
            if d.status_code != 200 or "html" in d.headers.get("Content-Type", ""):
                raise RuntimeError(f"{name} 받기 실패 {d.status_code}")
            with open(dst + ".part", "wb") as w:
                for ch in d.iter_content(1 << 20): w.write(ch)
            os.replace(dst + ".part", dst)
            print(f"  받음 {name} {os.path.getsize(dst)/1e6:.1f}MB", flush=True)
        out.append(name)
    return out


# ---------------- 넣기 ----------------
def 열번호(ref):
    n = 0
    for ch in re.match(r"[A-Z]+", ref).group(0): n = n * 26 + (ord(ch) - 64)
    return n - 1


def 글로(path, txt):
    """xlsx 첫 시트를 탭 구분 UTF-16 으로. 머리 줄을 찾아 우리 칸 순서로 놓는다."""
    with zipfile.ZipFile(path) as z:
        ss = []
        if "xl/sharedStrings.xml" in z.namelist():
            for _, el in ET.iterparse(z.open("xl/sharedStrings.xml")):
                if el.tag == NS + "si": ss.append("".join(t.text or "" for t in el.iter(NS + "t"))); el.clear()
        sheet = sorted(n for n in z.namelist() if n.startswith("xl/worksheets/sheet"))[0]
        머리 = None; 자리 = None; n = 0; 고친 = 0
        with open(txt, "w", encoding="utf-16", newline="") as w:
            for _, el in ET.iterparse(z.open(sheet)):
                if el.tag != NS + "row": continue
                vals = {}
                for c in el.findall(NS + "c"):
                    t = c.get("t"); ref = c.get("r")
                    if t == "inlineStr": v = "".join(x.text or "" for x in c.iter(NS + "t"))
                    else:
                        ve = c.find(NS + "v"); v = ve.text if ve is not None else ""
                        if t == "s" and v != "": v = ss[int(v)]
                    vals[열번호(ref)] = v or ""
                el.clear()
                if 머리 is None:
                    if "단지코드" in vals.values():
                        머리 = [vals.get(i, "").strip() for i in range(max(vals) + 1)]
                        모름 = [h for h in 머리 if h and h not in COLS]
                        if 모름: raise RuntimeError(f"모르는 칸 {모름} — 393 표에 칸을 더하고 다시")
                        자리 = [머리.index(cn) if cn in 머리 else None for cn in COLS]
                    continue
                줄 = []
                for i in 자리:
                    v = vals.get(i, "") if i is not None else ""
                    if "\t" in v or "\n" in v or "\r" in v: v = re.sub(r"[\t\r\n]+", " ", v); 고친 += 1
                    줄.append(v)
                if not 줄[4].strip(): continue
                w.write("\t".join(줄) + "\n"); n += 1
    if 머리 is None: raise RuntimeError("머리 줄(단지코드)을 못 찾음")
    return n, 고친, [c for c in COLS if c not in 머리]


def 넣기(cur, conn, name, seq):
    cur.execute("SELECT 1 FROM ops.kapt_cost_xlsx_file WHERE 파일 = %s", (name,))
    if cur.fetchone(): print(f"  이미 넣음 {name}"); return False
    os.makedirs(XDIR, exist_ok=True)
    txt = os.path.join(XDIR, "kcx.txt"); t0 = time.time()
    n, 고친, 없는칸 = 글로(os.path.join(OUT, name), txt)
    print(f"  {name}: {n:,}줄 · 글로 {time.time()-t0:.0f}초" + (f" · 칸 없음 {없는칸}" if 없는칸 else "") + (f" · 칸 안 줄바꿈 · 탭을 띄어쓰기로 {고친}" if 고친 else ""), flush=True)
    cur.execute("IF OBJECT_ID('silver.kapt_cost_xlsx_s') IS NOT NULL DROP TABLE silver.kapt_cost_xlsx_s; CREATE TABLE silver.kapt_cost_xlsx_s ("
                + ", ".join(f"[{c}] NVARCHAR(400) NULL" for c in COLS) + ")")
    conn.commit()
    cur.execute("BULK INSERT silver.kapt_cost_xlsx_s FROM '/bulk/kapt/_x/kcx.txt' WITH (DATAFILETYPE = 'widechar', FIELDTERMINATOR = '\\t', ROWTERMINATOR = '0x0a00', TABLOCK, BATCHSIZE = 200000, MAXERRORS = 0)")
    conn.commit()
    숫자 = lambda c: f"TRY_CONVERT(DECIMAL(20,4), TRY_CONVERT(FLOAT, NULLIF(LTRIM(RTRIM(s.[{c}])), N'')))"
    sel = ", ".join(f"[{c}] = {숫자(c)}" for c in NUM)
    해시 = "HASHBYTES('SHA2_256', CAST(CONCAT_WS(N'|', " + ", ".join(f"ISNULL(CAST([{c}] AS NVARCHAR(60)), N'')" for c in NUM) + ", [시도], [시군구], [읍면], [동리], [단지명]) AS VARBINARY(MAX)))"
    cur.execute(f"""SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#s') IS NOT NULL DROP TABLE #s;
SELECT kapt_code = CAST(LTRIM(RTRIM(s.[단지코드])) AS VARCHAR(20)), ym = CAST(LTRIM(RTRIM(s.[발생년월(YYYYMM)])) AS CHAR(6)),
       [시도] = NULLIF(s.[시도], N''), [시군구] = NULLIF(s.[시군구], N''), [읍면] = NULLIF(s.[읍면], N''), [동리] = NULLIF(s.[동리], N''), [단지명] = NULLIF(s.[단지명], N''),
       {sel},
       글자인데숫자아님 = {" + ".join(f"CASE WHEN NULLIF(LTRIM(RTRIM(s.[{c}])), N'') IS NOT NULL AND TRY_CONVERT(FLOAT, LTRIM(RTRIM(s.[{c}]))) IS NULL THEN 1 ELSE 0 END" for c in NUM)},
       rn = ROW_NUMBER() OVER (PARTITION BY LTRIM(RTRIM(s.[단지코드])), LTRIM(RTRIM(s.[발생년월(YYYYMM)])) ORDER BY (SELECT 0))
  INTO #s FROM silver.kapt_cost_xlsx_s s;
DECLARE @겹침 INT = (SELECT COUNT(*) FROM #s WHERE rn > 1), @숫자아님 INT = (SELECT SUM(글자인데숫자아님) FROM #s), @달틀림 INT = (SELECT COUNT(*) FROM #s WHERE ym NOT LIKE '[12][0-9][0-9][0-9][01][0-9]');
DELETE #s WHERE rn > 1 OR ym NOT LIKE '[12][0-9][0-9][0-9][01][0-9]' OR kapt_code = '';
ALTER TABLE #s ADD h VARBINARY(32) NULL;
UPDATE #s SET h = {해시};
DECLARE @a TABLE (act NVARCHAR(10));
MERGE silver.kapt_cost_xlsx AS t
USING #s AS s ON t.kapt_code = s.kapt_code AND t.ym = s.ym
WHEN MATCHED AND t.행해시 <> s.h THEN UPDATE SET {", ".join(f"[{c}] = s.[{c}]" for c in ['시도','시군구','읍면','동리','단지명'] + NUM)}, 파일 = %s, 행해시 = s.h, 바뀐때 = SYSDATETIME(), 바뀐수 = t.바뀐수 + 1
WHEN NOT MATCHED THEN INSERT (kapt_code, ym, {", ".join(f"[{c}]" for c in ['시도','시군구','읍면','동리','단지명'] + NUM)}, 파일, 행해시)
     VALUES (s.kapt_code, s.ym, {", ".join(f"s.[{c}]" for c in ['시도','시군구','읍면','동리','단지명'] + NUM)}, %s, s.h)
OUTPUT $action INTO @a;
DECLARE @줄 INT = (SELECT COUNT(*) FROM #s), @새로 INT = (SELECT COUNT(*) FROM @a WHERE act = 'INSERT'), @바뀜 INT = (SELECT COUNT(*) FROM @a WHERE act = 'UPDATE');
INSERT ops.kapt_cost_xlsx_file (파일, 글번호, 줄, 새로, 바뀜, 같음) VALUES (%s, %s, @줄, @새로, @바뀜, @줄 - @새로 - @바뀜);
SELECT @줄, @새로, @바뀜, @겹침, @숫자아님, @달틀림, (SELECT STRING_AGG(CONCAT(ym, ':', n), ' ') WITHIN GROUP (ORDER BY ym) FROM (SELECT ym, n = COUNT(*) FROM #s GROUP BY ym) z);""",
                (name, name, name, seq))
    r = cur.fetchone(); conn.commit()
    cur.execute("DROP TABLE silver.kapt_cost_xlsx_s"); conn.commit()
    os.remove(txt)
    print(f"    줄 {r[0]:,} · 새로 {r[1]:,} · 바뀜 {r[2]:,} · 같은 단지·달 겹침(뺌) {r[3]} · 숫자 아닌 글자(빈칸으로) {r[4]} · 달 틀림(뺌) {r[5]}\n    달별 {r[6]}", flush=True)
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--years", nargs="*")
    ap.add_argument("--no-fetch", action="store_true")
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    파일들 = []   # (연도, 글번호, 파일)
    if not a.no_fetch:
        s = requests.Session(); s.headers["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Teomoony-data"
        글 = 연도글(s, a.years)
        print(f"자료실 연도별 글: {', '.join(f'{y}={q}' for y, q in 글.items())}", flush=True)
        for y, q in 글.items():
            for name in 받기(s, q): 파일들.append((y, q, name))
    else:
        for name in sorted(os.listdir(OUT)):
            m = re.search(r"_(\d{4})\.xlsx$", name)
            if m and (not a.years or m.group(1) in a.years): 파일들.append((m.group(1), None, name))
    # 연도마다 가장 새 파일(이름 앞 날짜)만 넣는다
    최신 = {}
    for y, q, name in 파일들:
        if y not in 최신 or name > 최신[y][1]: 최신[y] = (q, name)
    e = env()
    conn = pymssql.connect(server=e.get("DB_HOST", "127.0.0.1"), port=int(e.get("DB_PORT", 11433)), user=e.get("DB_USER", "sa"),
                           password=e.get("DB_PASSWORD", ""), database=e.get("DB_NAME", "Teomoony"), charset="UTF-8", autocommit=False)
    cur = conn.cursor(); 넣음 = 0
    for y in sorted(최신):
        q, name = 최신[y]
        if 넣기(cur, conn, name, q): 넣음 += 1
    conn.close()
    print(f"끝 — 넣은 파일 {넣음}", flush=True)
    sys.exit(0 if 넣음 else 3)


if __name__ == "__main__":
    main()
