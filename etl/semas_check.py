#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""semas_check - 소상공인 상가(상권)정보 전국 파일(data.go.kr 15083033, 분기) 새 판 확인 → 있으면 받아서 분기 갱신 (2026-10-28 사장님 "1 너가봐")
  py semas_check.py          (수집 일정 '상가 분기 파일' · daily 06:10 · 새 것 없으면 종료코드 3 = 건너뜀)
★ 공식 내려받기 길 그대로: 자료 페이지(파일 이름의 기준일) → selectFileDataDownload.do(누리집 '다운로드' 단추가 부르는 것) → fileDownload.do.
  매일은 **페이지만** 본다(기준일이 새로울 때만 내려받기 요청 — 내려받기 수를 부풀리지 않게).
★ 받으면 load_semas_file.py --refresh: 새것이 이긴다(파일 기준일보다 옛 줄만) · 빠진 점포는 닫기만(지우지 않음) · 덜 온 파일이면 아무것도 안 바꾸고 멈춤.
★ 끝나면 zip · 풀어 둔 글 지움(디스크). 기준일은 _semas_file_base.txt 에(실패하면 안 바꿔 다음 날 다시)."""
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
log(f"끝 — 기준일 {last} → {base} · zip 지움")
