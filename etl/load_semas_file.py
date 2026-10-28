# -*- coding: utf-8 -*-
"""load_semas_file - 소상공인 상가(상권)정보 **전국 파일**(data.go.kr 15083033, 분기) → silver.semas_store (2026-10-26 사장님 "너가받아봐")
  py load_semas_file.py ..\\deploy\\bulk\\semas\\semas_20260630.zip --base 20260630
  ★ 파일 그대로 먼저 hub.semas_file 에 넣고(글자 그대로 · 시도 파일 이름 함께), 거기서 우리 표 모양으로 바꾼다 — API 적재기(load_semas.py)와 같은 규칙:
    앞뒤 빈칸 자름 · 빈 글자 = NULL · 지번코드는 숫자 19자리일 때만 PNU(조용히 틀린 PNU 는 NULL 보다 나쁘다) · 좌표는 소수 8자리.
  ★ **이미 지금 줄이 있는 점포는 건드리지 않는다.** 지금 있는 서울 · 경기 줄은 10월에 API 로 받은 것이라 이 파일(6월 말 기준)보다 새것이다
    — 옛 파일로 덮으면 되돌아간다. 이 파일에 없는 점포도 닫지 않는다(7~10월에 새로 연 곳일 수 있다). 없는 점포만 새로 넣는다.
  ★ collected_at = 파일 기준일(--base). 받은 날이 아니라 '이 날 기준 영업 중' 이 정확한 뜻이라."""
import argparse, csv, io, os, sys, time, zipfile
from svc_publish import env, ms_conn
def log(*a): print(f"[{time.strftime('%H:%M:%S')}]", *a, flush=True)
ap = argparse.ArgumentParser(); ap.add_argument("zip"); ap.add_argument("--base", required=True)
# ★ 2026-10-28 분기 갱신(semas_check.py 가 씀): **새것이 이긴다** — 파일 기준일보다 옛 줄만 건드린다(API 로 더 늦게 받은 줄은 그대로).
#   ① 파일에 있고 값이 다르면: 옛 줄 닫고(is_current=0 · valid_to) 새 줄 ② 파일에 없으면: 그 기준일에 목록에서 빠진 것 → 닫기만(지우지 않음 · 이력 그대로)
#   ③ 파일이 덜 왔으면(시도 하나가 빠지거나 지금의 70% 미만) **아무것도 안 바꾸고 멈춘다** — 덜 온 파일로 한 시도를 통째로 닫지 않게.
ap.add_argument("--refresh", action="store_true"); a = ap.parse_args()
ms = ms_conn(env()); cur = ms.cursor()
z = zipfile.ZipFile(a.zip)
files = [i for i in z.infolist() if i.filename.lower().endswith(".csv")]
def nm(i):
    try: return i.filename if i.flag_bits & 0x800 else i.filename.encode("cp437").decode("cp949")
    except Exception: return i.filename
hdr = None
cur.execute("IF OBJECT_ID('hub.semas_file') IS NOT NULL DROP TABLE hub.semas_file")
# ★ 2026-10-26 여러 줄 INSERT 로 넣으니 강원 한 파일(30만 줄)에 20분이 넘었다(DB 가 다른 적재로 바쁨) → load_hub 처럼 **풀어서 DB 안 BULK INSERT**.
#   Linux SQL Server 의 BULK INSERT 는 UTF-8 을 못 받아 UTF-16(BOM)으로 바꿔 쓴다 — 글자는 그대로(인코딩만). 칸 구분은 탭
#   (전국 277만 줄에 탭 · 줄바꿈이 든 값 0 — 미리 셌다. '|' 는 3줄에 있어 못 쓴다). 탭이 든 값이 나오면 멈춘다(값을 고치지 않는다).
xdir = os.path.join(os.path.dirname(os.path.abspath(a.zip)), "_x"); os.makedirs(xdir, exist_ok=True)
txt = os.path.join(xdir, "semas_file.txt")
t0 = time.time(); total = 0
with open(txt, "w", encoding="utf-16", newline="") as out:
    for i in files:
        f = io.TextIOWrapper(z.open(i), encoding="utf-8-sig", newline="")
        rd = csv.reader(f); h = next(rd)
        if hdr is None: hdr = h
        elif h != hdr: sys.exit(f"칸이 다르다: {nm(i)}")
        fn = os.path.basename(nm(i)); n = 0
        for r in rd:
            if len(r) != len(hdr): sys.exit(f"{fn} {n+2}번째 줄 칸 수 {len(r)} ≠ {len(hdr)}")
            if any(("\t" in x) or ("\n" in x) or ("\r" in x) for x in r): sys.exit(f"{fn} {n+2}번째 줄에 탭/줄바꿈 — 멈춤")
            out.write("\t".join(r + [fn]) + "\n"); n += 1
        total += n; log(f"{fn}: {n:,}줄")
cur.execute("CREATE TABLE hub.semas_file (" + ", ".join(f"[{c}] NVARCHAR(400) NULL" for c in hdr) + ", [파일] NVARCHAR(100) NULL) WITH (DATA_COMPRESSION = PAGE)")
cur.execute("""BULK INSERT hub.semas_file FROM '/bulk/semas/_x/semas_file.txt'
  WITH (DATAFILETYPE = 'widechar', FIELDTERMINATOR = '\t', ROWTERMINATOR = '0x0a00', TABLOCK, BATCHSIZE = 500000, MAXERRORS = 0);""")
cur.execute("SELECT COUNT_BIG(*) FROM hub.semas_file"); n2 = cur.fetchone()[0]
if n2 != total: sys.exit(f"넣은 줄 {n2:,} ≠ 파일 줄 {total:,}")
os.remove(txt)
log(f"파일 {len(files)}개 · {total:,}줄 · {time.time()-t0:.0f}초 — 우리 표로")
T = lambda c: f"NULLIF(LTRIM(RTRIM([{c}])), N'')"
cur.execute(f"""SET XACT_ABORT ON;
IF OBJECT_ID('tempdb..#n') IS NOT NULL DROP TABLE #n;
SELECT bizes_id = CAST({T('상가업소번호')} AS VARCHAR(30)), bizes_nm = CAST({T('상호명')} AS NVARCHAR(200)), brch_nm = CAST({T('지점명')} AS NVARCHAR(100)),
       inds_lcls_cd = CAST({T('상권업종대분류코드')} AS VARCHAR(4)), inds_lcls_nm = CAST({T('상권업종대분류명')} AS NVARCHAR(60)),
       inds_mcls_cd = CAST({T('상권업종중분류코드')} AS VARCHAR(6)), inds_mcls_nm = CAST({T('상권업종중분류명')} AS NVARCHAR(60)),
       inds_scls_cd = CAST({T('상권업종소분류코드')} AS VARCHAR(8)), inds_scls_nm = CAST({T('상권업종소분류명')} AS NVARCHAR(80)),
       ksic_cd = CAST({T('표준산업분류코드')} AS VARCHAR(10)), ksic_nm = CAST({T('표준산업분류명')} AS NVARCHAR(100)),
       signgu_cd = CAST({T('시군구코드')} AS CHAR(5)), adong_cd = CAST({T('행정동코드')} AS VARCHAR(10)), adong_nm = CAST({T('행정동명')} AS NVARCHAR(60)),
       ldong_cd = CAST({T('법정동코드')} AS CHAR(10)), ldong_nm = CAST({T('법정동명')} AS NVARCHAR(60)),
       pnu = CASE WHEN LEN({T('지번코드')}) = 19 AND {T('지번코드')} NOT LIKE '%[^0-9]%' THEN CAST({T('지번코드')} AS CHAR(19)) END,
       lno_adr = CAST({T('지번주소')} AS NVARCHAR(300)), bld_mng_no = CAST({T('건물관리번호')} AS VARCHAR(30)), bld_nm = CAST({T('건물명')} AS NVARCHAR(200)),
       rdnm_adr = CAST({T('도로명주소')} AS NVARCHAR(300)), flr_no = CAST({T('층정보')} AS NVARCHAR(20)), ho_no = CAST({T('호정보')} AS NVARCHAR(20)),
       lon = CAST(ROUND(TRY_CONVERT(FLOAT, {T('경도')}), 8) AS DECIMAL(12, 8)), lat = CAST(ROUND(TRY_CONVERT(FLOAT, {T('위도')}), 8) AS DECIMAL(11, 8)),
       rn = ROW_NUMBER() OVER (PARTITION BY {T('상가업소번호')} ORDER BY [파일])
  INTO #n FROM hub.semas_file;
SELECT 줄 = COUNT(*), 겹침 = SUM(CASE WHEN rn > 1 THEN 1 ELSE 0 END), 번호없음 = SUM(CASE WHEN bizes_id IS NULL THEN 1 ELSE 0 END),
       PNU있음 = SUM(CASE WHEN pnu IS NOT NULL THEN 1 ELSE 0 END), 좌표있음 = SUM(CASE WHEN lon IS NOT NULL AND lat IS NOT NULL THEN 1 ELSE 0 END),
       이미있음 = (SELECT COUNT(*) FROM #n n2 WHERE n2.rn = 1 AND EXISTS (SELECT 1 FROM silver.semas_store s WHERE s.is_current = 1 AND s.bizes_id = n2.bizes_id))
  FROM #n;""")
r = cur.fetchone(); log("파일 줄 {:,} · 같은 번호 겹침 {:,} · 번호 없음 {:,} · PNU {:,} · 좌표 {:,} · 이미 있음(건드리지 않음) {:,}".format(*r))
cols = ["bizes_id", "bizes_nm", "brch_nm", "inds_lcls_cd", "inds_lcls_nm", "inds_mcls_cd", "inds_mcls_nm", "inds_scls_cd", "inds_scls_nm", "ksic_cd", "ksic_nm",
        "signgu_cd", "adong_cd", "adong_nm", "ldong_cd", "ldong_nm", "pnu", "lno_adr", "bld_mng_no", "bld_nm", "rdnm_adr", "flr_no", "ho_no", "lon", "lat"]
hexpr = "HASHBYTES('SHA2_256', CAST(CONCAT_WS(N'|', " + ", ".join(f"ISNULL(CAST(n.[{c}] AS NVARCHAR(400)), N'')" for c in cols) + ") AS VARBINARY(MAX)))"
st = time.time()
if a.refresh:
    cur.execute("""SELECT k = COALESCE(f.s, c.s), 파일 = ISNULL(f.n, 0), 지금 = ISNULL(c.n, 0) FROM
        (SELECT s = LEFT(signgu_cd, 2), n = COUNT(*) FROM #n WHERE rn = 1 AND bizes_id IS NOT NULL GROUP BY LEFT(signgu_cd, 2)) f
        FULL JOIN (SELECT s = LEFT(signgu_cd, 2), n = COUNT(*) FROM silver.semas_store WHERE is_current = 1 GROUP BY LEFT(signgu_cd, 2)) c ON c.s = f.s
        ORDER BY 1""")
    짝 = cur.fetchall(); 모자람 = [f"{k}: 파일 {f:,} · 지금 {c:,}" for k, f, c in 짝 if k and c >= 1000 and f < c * 0.7]
    log("시도별 파일/지금: " + " · ".join(f"{k}:{f:,}/{c:,}" for k, f, c in 짝))
    if 모자람: sys.exit("파일이 덜 온 것 같다 — 아무것도 안 바꾸고 멈춤: " + " · ".join(모자람))
    cur.execute(f"""SET XACT_ABORT ON; BEGIN TRAN;
UPDATE s SET is_current = 0, valid_to = SYSDATETIME()
  FROM silver.semas_store s JOIN #n n ON n.rn = 1 AND n.bizes_id = s.bizes_id
 WHERE s.is_current = 1 AND s.collected_at < %s AND s.row_hash <> {hexpr};
DECLARE @바뀜 INT = @@ROWCOUNT;
UPDATE s SET is_current = 0, valid_to = SYSDATETIME()
  FROM silver.semas_store s
 WHERE s.is_current = 1 AND s.collected_at < %s AND NOT EXISTS (SELECT 1 FROM #n n WHERE n.rn = 1 AND n.bizes_id = s.bizes_id);
DECLARE @빠짐 INT = @@ROWCOUNT;
SELECT @바뀜, @빠짐;""", (a.base, a.base))   # ★ 아직 COMMIT 안 함 — 아래 새 줄 넣기까지 한 묶음(중간에 죽으면 닫은 것도 되돌아감)
    바뀜, 빠짐 = cur.fetchone()
    log(f"분기 갱신 — 값 바뀐 점포 옛 줄 닫음 {바뀜:,} · 파일에서 빠진 점포 닫음 {빠짐:,} · {time.time()-st:.0f}초")
cur.execute(f"""INSERT INTO silver.semas_store ({', '.join(cols)}, geog, collected_at, row_hash)
SELECT {', '.join('n.' + c for c in cols)},
       CASE WHEN n.lat BETWEEN -90 AND 90 AND n.lon BETWEEN -180 AND 180 THEN geography::Point(n.lat, n.lon, 4326) END,
       %s, {hexpr}
  FROM #n n
 WHERE n.rn = 1 AND n.bizes_id IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM silver.semas_store s WHERE s.is_current = 1 AND s.bizes_id = n.bizes_id);
SELECT @@ROWCOUNT;""", (a.base,))
new = cur.fetchone()[0]
if a.refresh: cur.execute("COMMIT")
log(f"새로 넣음 {new:,} · {time.time()-st:.0f}초")
cur.execute("SELECT LEFT(signgu_cd, 2), COUNT(*) FROM silver.semas_store WHERE is_current = 1 GROUP BY LEFT(signgu_cd, 2) ORDER BY 1")
log("시도별 지금 점포: " + " · ".join(f"{s}:{n:,}" for s, n in cur.fetchall()))
