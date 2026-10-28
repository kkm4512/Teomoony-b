#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""semas_check - 소상공인 상가(상권)정보 전국 파일(data.go.kr 15083033, 분기) 새 판 확인 → 있으면 받아서 분기 갱신 (2026-10-28 사장님 "1 너가봐")
  py semas_check.py          (수집 일정 '상가 분기 파일' · daily 06:10 · 새 것 없으면 종료코드 3 = 건너뜀)
★ 공식 내려받기 길 그대로: 자료 페이지(파일 이름의 기준일) → selectFileDataDownload.do(누리집 '다운로드' 단추가 부르는 것) → fileDownload.do.
  매일은 **페이지만** 본다(기준일이 새로울 때만 내려받기 요청 — 내려받기 수를 부풀리지 않게).
★ 받으면 load_semas_file.py --refresh: 새것이 이긴다(파일 기준일보다 옛 줄만) · 빠진 점포는 닫기만(지우지 않음) · 덜 온 파일이면 아무것도 안 바꾸고 멈춤.
★ 끝나면 zip · 풀어 둔 글 지움(디스크) → 매칭테이블 다시 → 발행된 상세 전부 '상세 다시' 표에(뒤에서 천천히). 기준일은 _semas_file_base.txt 에(실패하면 안 바꿔 다음 날 다시)."""
import json, os, re, shutil, subprocess, sys, time, urllib.parse, urllib.request, zipfile
HERE = os.path.dirname(os.path.abspath(__file__))
BULK = os.path.join(HERE, "..", "deploy", "bulk", "semas")
STATE = os.path.join(HERE, "_semas_file_base.txt")
PAGE = "https://www.data.go.kr/data/15083033/fileData.do"
UA = {"User-Agent": "Mozilla/5.0 (teomoony non-commercial)"}
def log(*a): print(f"[{time.strftime('%H:%M:%S')}]", *a, flush=True)
def get(u, data=None, hdr=None, timeout=60):
    return urllib.request.urlopen(urllib.request.Request(u, data=data, headers={**UA, **(hdr or {})}), timeout=timeout)

last = open(STATE).read().strip() if os.path.exists(STATE) else "20260630"   # 10-26 에 넣은 판
h = get(PAGE).read().decode("utf-8", "replace")
bases = sorted(set(re.findall(r"상가\(상권\)정보_(\d{8})", h)))
uddi = re.search(r'id="publicDataDetailPk"[^>]*value="(uddi:[0-9a-f\-]+)"', h)
nxt = re.search(r"차기 등록 예정일</strong>\s*<div class=\"value\">([^<]+)<", h)
if not bases or not uddi: sys.exit("페이지 모양이 바뀌었다 — 파일 이름(기준일)이나 자료 번호를 못 찾음")
base = bases[-1]
log(f"페이지 기준일 {base} · 우리 {last} · 차기 등록 예정일 {nxt.group(1).strip() if nxt else '?'}")
if base <= last:
    log("출처에 새 것 없음"); sys.exit(3)

free = shutil.disk_usage(HERE).free / 2**30
if free < 15: log(f"디스크 남은 {free:.0f}GB < 15GB — 건너뜀"); sys.exit(3)
body = urllib.parse.urlencode({"publicDataDetailPk": uddi.group(1), "publicDataPk": "15083033", "atchFileId": "", "fileDetailSn": "1", "publicDataTyCode": "PR0051"}).encode()
d = json.loads(get("https://www.data.go.kr/tcs/dss/selectFileDataDownload.do", body, {"Referer": PAGE, "X-Requested-With": "XMLHttpRequest"}).read().decode("utf-8", "replace"))
nm = (d.get("dataSetFileDetailInfo") or {}).get("dataNm") or ""
if not d.get("status") or not d.get("atchFileId"): sys.exit(f"내려받기 정보를 못 받음: {str(d)[:200]}")
if base not in nm: sys.exit(f"내려받기 파일 이름({nm})이 페이지 기준일({base})과 다르다 — 멈춤")
os.makedirs(BULK, exist_ok=True)
z = os.path.join(BULK, f"semas_{base}.zip")
if not (os.path.exists(z) and zipfile.is_zipfile(z)):
    u = "https://www.data.go.kr/cmm/cmm/fileDownload.do?" + urllib.parse.urlencode({"atchFileId": d["atchFileId"], "fileDetailSn": d.get("fileDetailSn") or "1", "dataNm": nm})
    t = time.time(); part = z + ".part"
    with get(u, hdr={"Referer": PAGE}, timeout=600) as r, open(part, "wb") as f: shutil.copyfileobj(r, f, 1 << 20)
    if not zipfile.is_zipfile(part): os.remove(part); sys.exit("받은 것이 zip 이 아니다 — 멈춤")
    os.replace(part, z); log(f"받음 {os.path.getsize(z)/2**20:,.0f}MB · {time.time()-t:.0f}초 · {nm}")
else:
    log(f"이미 받아 둔 zip 다시 씀 {z}")
r = subprocess.run([sys.executable, os.path.join(HERE, "load_semas_file.py"), z, "--base", base, "--refresh"], cwd=HERE)
if r.returncode != 0: sys.exit(f"적재 실패(종료코드 {r.returncode}) — 기준일 안 바꿈 · zip 남김(다음 때 다시)")
open(STATE, "w").write(base + "\n")
os.remove(z); shutil.rmtree(os.path.join(BULK, "_x"), ignore_errors=True)
log(f"적재 끝 — 기준일 {last} → {base} · zip 지움")
# ★ 10-28 사장님 "너판단으로 ㄱㄱ": 상세에는 상권도 담겨 있다 → ① 매칭테이블(nm)을 **이 적재 뒤에** 다시 만들고
#   ② 이미 발행된 상세 전부를 '상세 다시' 표에 적는다 — 수집 일정 '상세 다시(밀린 것)'(cl-svc-dirty-par)가 뒤에서 천천히 비운다(실거래 바뀜이 늘 먼저).
#   nm 이 다른 실행으로 돌고 있으면(잠금) 그건 적재 전 상가를 읽었을 수 있다 → 끝날 때까지 기다렸다가 **우리 것**을 한 번 더 돌린다(최대 3시간).
for 번 in range(36):
    r = subprocess.run([sys.executable, os.path.join(HERE, "nm_build.py")], cwd=HERE, capture_output=True, text=True, encoding="utf-8", errors="replace")
    print(r.stdout[-3000:], r.stderr[-2000:], flush=True)
    if r.returncode == 0 and "다른 nm_build 가 도는 중" not in r.stdout: break
    if r.returncode != 0: sys.exit(f"매칭테이블 다시 만들기 실패(종료코드 {r.returncode}) — 상가는 들어갔음 · 상세 다시 표시는 안 함")
    log("다른 nm_build 가 도는 중 — 5분 뒤 다시"); time.sleep(300)
else:
    sys.exit("매칭테이블을 3시간 동안 못 다시 만듦 — 상가는 들어갔음 · 상세 다시 표시는 안 함")
from svc_publish import env, pg_conn
pg = pg_conn(env())
with pg.cursor() as c:
    c.execute("CREATE TABLE IF NOT EXISTS svc.detail_dirty (complex_id int PRIMARY KEY, why text NOT NULL, at timestamptz NOT NULL DEFAULT now())")
    c.execute("""INSERT INTO svc.detail_dirty (complex_id, why) SELECT complex_id, %s FROM svc.complex_json WHERE kind = 'detail'
                 ON CONFLICT (complex_id) DO NOTHING""", (f"상가 새 판 {base}",))
    log(f"상세 다시 표에 적음 {c.rowcount:,} — 뒤에서 차례로 다시 발행")
pg.commit()
log("끝")
