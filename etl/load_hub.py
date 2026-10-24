# -*- coding: utf-8 -*-
"""load_hub - 건축HUB 대용량 월별 전국 파일(hub_bulk.py 가 받은 zip) → hub.t<코드> **버전 표**  2026-10-24

  사장님 "옛날 것부터 수집하면서 달라진 칼럼을 액션로그식으로". 건축HUB 는 매달 **전국 그대로**를 떠서 주고 최근 3개월만 남긴다.
  → 달마다 받은 파일을 **오래된 달부터** 이 표에 얹는다. 같은 줄(모든 칸이 같음)은 한 번만 두고 '처음월 ~ 마지막월' 만 늘린다.
     바뀐 줄은 새 줄로 들어가고(처음월 = 그 달), 옛 줄은 마지막월에서 멈춘다 → 원본 그대로의 **월별 버전**. 변경 로그는 여기서 뽑는다.

  py load_hub.py --code 0303 --month 202607          한 종류 · 한 달
  py load_hub.py --all                               받아 둔 zip 전부(달 오래된 순 · 종류별)
  py load_hub.py --all --cat 건축물대장 --only 표제부

  ★ 칸 = hub_spec.json(사이트의 '설명' 표, 칸 순서 그대로). 이름의 단위 괄호만 뗀다('대지_면적(㎡)' → 대지_면적). 값은 **글자 그대로**(NVARCHAR) — 숫자로 바꾸다 틀리지 않게.
  ★ 줄 해시 = 모든 칸(생성_일자 빼고 — 매달 바뀌는 생성 표시라 버전을 가짜로 만든다)을 '|' 로 이은 SHA-256.
  ★ 불러오기는 DB 안 BULK INSERT(UTF-8 · '|' · LF). zip 은 deploy/bulk/hub/_x 에 잠깐 풀고 다 넣으면 지운다(zip 원본은 그대로 둔다).
  ★ 같은 달을 두 번 넣어도 같다(이미 그 달까지 본 줄은 그대로).
"""
import argparse, glob, json, os, re, sys, time, zipfile
import pymssql

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "deploy", "bulk", "hub"))
SPEC = json.load(open(os.path.join(HERE, "hub_spec.json"), encoding="utf-8"))


def env():
    d = {}
    for line in open(os.path.join(HERE, "..", ".env"), encoding="utf-8-sig"):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1); d[k.strip()] = v.strip()
    return d


def 칸이름(spec):
    out, seen = [], {}
    for nm, _t in spec["칸"]:
        n = re.sub(r"\(.*?\)", "", nm).strip().replace(" ", "_")
        if n in seen:
            seen[n] += 1; n = f"{n}_{seen[n]}"
        else:
            seen[n] = 1
        out.append(n)
    return out


def ts():
    return time.strftime("%H:%M:%S")


def 표만들기(cur, code, cols):
    """hub.t<code>: 원문 칸(NVARCHAR) + 행해시 · 처음월 · 마지막월. hub.s<code>: 불러오기 받침(같은 칸)"""
    defs = ",\n  ".join(f"[{c}] NVARCHAR({'2000' if i else '40'}) NULL" for i, c in enumerate(cols))
    cur.execute(f"""IF SCHEMA_ID('hub') IS NULL EXEC('CREATE SCHEMA hub');""")
    cur.execute(f"""IF OBJECT_ID('hub.t{code}') IS NULL
CREATE TABLE hub.t{code} (
  행_sk BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT pk_hub_t{code} PRIMARY KEY,
  {defs},
  행해시 BINARY(32) NOT NULL,
  처음월 CHAR(6) NOT NULL,
  마지막월 CHAR(6) NULL          -- 마지막으로 보인 달 · NULL = 가장 최근에 넣은 달에도 있음(지금 줄)
);""")
    # 2026-10-24 19:50 옮기기: 처음 만든 표는 '매달 모든 줄의 마지막월을 고쳐 쓰는' 방식(NOT NULL + 해시 유일)이었다 —
    #  649만 줄 표에서 한 달에 17분. 사라진 줄만 닫는 방식으로 바꾼다. 가장 최근 달까지 있던 줄 = NULL.
    cur.execute(f"""IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('hub.t{code}') AND name = N'마지막월' AND is_nullable = 0)
BEGIN
  IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_hub_t{code}_key' AND object_id = OBJECT_ID('hub.t{code}')) DROP INDEX ix_hub_t{code}_key ON hub.t{code};
  IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_hub_t{code}_hash' AND object_id = OBJECT_ID('hub.t{code}')) DROP INDEX ix_hub_t{code}_hash ON hub.t{code};
  ALTER TABLE hub.t{code} ALTER COLUMN 마지막월 CHAR(6) NULL;
  EXEC(N'UPDATE hub.t{code} SET 마지막월 = NULL WHERE 마지막월 = (SELECT MAX(월) FROM hub.month_done WHERE code = ''{code}'')');
END""")
    cur.execute(f"""IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ux_hub_t{code}_now' AND object_id = OBJECT_ID('hub.t{code}'))
CREATE UNIQUE INDEX ux_hub_t{code}_now ON hub.t{code} (행해시) WHERE 마지막월 IS NULL;""")
    cur.execute(f"""IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_hub_t{code}_h' AND object_id = OBJECT_ID('hub.t{code}'))
CREATE INDEX ix_hub_t{code}_h ON hub.t{code} (행해시) INCLUDE (처음월, 마지막월);""")
    cur.execute(f"""IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_hub_t{code}_key' AND object_id = OBJECT_ID('hub.t{code}'))
CREATE INDEX ix_hub_t{code}_key ON hub.t{code} ([{cols[0]}]) INCLUDE (처음월, 마지막월);""")
    cur.execute(f"IF OBJECT_ID('hub.s{code}') IS NOT NULL DROP TABLE hub.s{code};")   # 받침표(파생 · 매번 새로)
    sdefs = ",\n  ".join(f"[{c}] NVARCHAR(2000) NULL" for c in cols)
    cur.execute(f"CREATE TABLE hub.s{code} (\n  {sdefs}\n);")


def 넣기(conn, code, month, zpath):
    spec = SPEC[code]; cols = 칸이름(spec)
    cur = conn.cursor()
    if 표있나(cur, "hub.month_done"):
        cur.execute("SELECT 1 FROM hub.month_done WHERE code = %s AND 월 = %s", (code, month))
        if cur.fetchone():
            print(f"  = {code} {spec['분류']} {spec['이름']} {month} 이미 넣음", flush=True); return
        cur.execute("SELECT MAX(월) FROM hub.month_done WHERE code = %s", (code,))
        last = cur.fetchone()[0]
        if last and last > month:
            raise RuntimeError(f"{month} 보다 뒤 달({last})이 이미 들어가 있다 — 달은 오래된 순으로만 얹는다")
    t0 = time.time()
    xdir = os.path.join(ROOT, "_x"); os.makedirs(xdir, exist_ok=True)
    with zipfile.ZipFile(zpath) as z:
        names = [i for i in z.infolist() if not i.is_dir()]
        if len(names) != 1:
            raise RuntimeError(f"zip 안 파일이 {len(names)}개 — 하나여야 한다: {[i.filename for i in names]}")
        txt = os.path.join(xdir, f"{code}_{month}.txt")
        # ★ Linux SQL Server 의 BULK INSERT 는 UTF-8 코드페이지를 못 받는다(CODEPAGE 불가 · char 는 글자가 깨짐 — 시험에서 확인).
        #   그래서 풀면서 **UTF-16(BOM)** 으로 바꿔 쓴다(DATAFILETYPE = 'widechar' · 줄 끝 0x0a00). 글자는 그대로다(인코딩만 바뀜).
        import io
        with z.open(names[0]) as src, open(txt, "w", encoding="utf-16", newline="") as dst:   # BOM 이 있어야 widechar 로 읽는다(없으면 char 로 보고 깨짐 — 시험)
            rd = io.TextIOWrapper(src, encoding="utf-8", errors="strict", newline="")
            while True:
                t_ = rd.read(1 << 22)
                if not t_: break
                dst.write(t_)
    표만들기(cur, code, cols); conn.commit()
    inner = f"/bulk/hub/_x/{code}_{month}.txt"
    cur.execute(f"""BULK INSERT hub.s{code} FROM '{inner}'
      WITH (DATAFILETYPE = 'widechar', FIELDTERMINATOR = '|', ROWTERMINATOR = '0x0a00', TABLOCK, BATCHSIZE = 500000, MAXERRORS = 0);""")
    conn.commit()
    cur.execute(f"SELECT COUNT_BIG(*) FROM hub.s{code}"); n = cur.fetchone()[0]
    os.remove(txt)
    hcols = [c for c in cols if c != "생성_일자"]
    hexpr = "HASHBYTES('SHA2_256', CAST(CONCAT_WS(N'|', " + ", ".join(f"ISNULL(CAST([{c}] AS NVARCHAR(4000)), N'')" for c in hcols) + ") AS VARBINARY(MAX)))"
    # ★ 2026-10-24 19:50: 매달 모든 줄을 고쳐 쓰지 않는다(649만 줄에 17분). 지금 줄(마지막월 NULL) 중 이번 달에 **없는 것만 닫고**(마지막월 = 앞 달),
    #   이번 달에 처음 보이는 해시만 새 줄로 넣는다. 해시는 받침표에서 두 번 셈 — 넓은 칸을 tempdb 로 옮기지 않으려고.
    cur.execute(f"""IF OBJECT_ID('tempdb..#h') IS NOT NULL DROP TABLE #h;
SELECT DISTINCT h = {hexpr} INTO #h FROM hub.s{code};
CREATE UNIQUE CLUSTERED INDEX x ON #h (h);
DECLARE @prev CHAR(6) = CONVERT(CHAR(6), DATEADD(MONTH, -1, CAST(%s + '01' AS DATE)), 112);
UPDATE t SET 마지막월 = @prev FROM hub.t{code} t
 WHERE t.마지막월 IS NULL AND NOT EXISTS (SELECT 1 FROM #h s WHERE s.h = t.행해시);
DECLARE @닫음 BIGINT = @@ROWCOUNT;
INSERT hub.t{code} ({", ".join(f"[{c}]" for c in cols)}, 행해시, 처음월, 마지막월)
SELECT {", ".join(f"[{c}]" for c in cols)}, h, %s, NULL
  FROM (SELECT *, h = {hexpr}, rn = ROW_NUMBER() OVER (PARTITION BY {hexpr} ORDER BY (SELECT 0)) FROM hub.s{code}) s
 WHERE s.rn = 1 AND NOT EXISTS (SELECT 1 FROM hub.t{code} t WHERE t.행해시 = s.h AND t.마지막월 IS NULL);
SELECT 새줄 = @@ROWCOUNT, 닫음 = @닫음;""", (month, month))
    새, 닫음 = cur.fetchone()
    cur.execute(f"DROP TABLE hub.s{code}")
    cur.execute("""IF OBJECT_ID('hub.month_done') IS NULL CREATE TABLE hub.month_done (code CHAR(4) NOT NULL, 월 CHAR(6) NOT NULL, 줄 BIGINT, 새줄 BIGINT, 초 INT, 넣은때 DATETIME2(0) DEFAULT SYSDATETIME(), CONSTRAINT pk_hub_month_done PRIMARY KEY (code, 월));
                   INSERT hub.month_done (code, 월, 줄, 새줄, 초) VALUES (%s, %s, %s, %s, %s);""", (code, month, n, 새, int(time.time() - t0)))
    conn.commit()
    print(f"  ✔ [{ts()}] {code} {spec['분류']} {spec['이름']} {month}: {n:,}줄 · 새 버전 {새:,} · 사라짐 {닫음:,} · {time.time()-t0:.0f}초", flush=True)


def 표있나(cur, name):
    cur.execute("SELECT OBJECT_ID(%s)", (name,)); return cur.fetchone()[0] is not None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--code"); ap.add_argument("--month")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--cat", nargs="*"); ap.add_argument("--only", nargs="*")
    a = ap.parse_args()
    e = env()
    conn = pymssql.connect(server=e.get("DB_HOST", "127.0.0.1"), port=int(e.get("DB_PORT", 11433)), user=e.get("DB_USER", "sa"),
                           password=e.get("DB_PASSWORD", ""), database=e.get("DB_NAME", "Teomoony"), charset="UTF-8", autocommit=False, timeout=0)
    # 받은 zip ↔ 코드: 파일 이름의 '분류_이름' 으로 spec 을 찾는다(이름은 사이트 그대로)
    일 = []
    for z in sorted(glob.glob(os.path.join(ROOT, "2*", "*.zip"))):
        month = os.path.basename(os.path.dirname(z))
        base = os.path.basename(z)
        for code, sp in SPEC.items():
            if f"_{sp['분류']}_{sp['이름']}+(" in base or f"_{sp['분류']}_{sp['이름']}(" in base:
                일.append((month, code, z)); break
    if a.code: 일 = [x for x in 일 if x[1] == a.code]
    if a.month: 일 = [x for x in 일 if x[0] == a.month]
    if a.cat: 일 = [x for x in 일 if SPEC[x[1]]["분류"] in a.cat]
    if a.only: 일 = [x for x in 일 if SPEC[x[1]]["이름"] in a.only]
    if not (a.all or a.code):
        sys.exit("--all 또는 --code")
    일.sort(key=lambda x: (x[1], x[0]))      # 종류마다 오래된 달부터 — 버전 순서가 맞아야 한다
    print(f"[{ts()}] 넣을 것 {len(일)}", flush=True)
    bad = 0
    for month, code, z in 일:
        try:
            넣기(conn, code, month, z)
        except Exception as ex:
            bad += 1; conn.rollback()
            print(f"  !! {code} {month} {SPEC[code]['분류']} {SPEC[code]['이름']}: {str(ex)[:300]}", flush=True)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
