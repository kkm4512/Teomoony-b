# -*- coding: utf-8 -*-
"""hub_latest - 아주 큰 허브 파일(공동주택가격 · 전유공용면적)은 **최신 한 달 · 필요한 칸만** 넣는다 (2026-10-25 사장님 "1 ㄱㄱ")
  py hub_latest.py --code 0308            (기본: 받아 둔 달 중 가장 최근)
  py hub_latest.py --code 0306 --month 202609

  ★ 왜: 공동주택가격은 달마다 zip 5.9GB(풀면 수십 GB) — load_hub 처럼 석 달을 버전 표로 쌓으면 디스크(C: 남은 357GB)가 위험.
       파일 한 달 안에 지난 기준일 가격도 들어 있다(호 × 기준일) → 이력은 그 한 달로 본다. 허브의 '월별 버전'(파일이 바뀐 이력)만 이 둘은 없다.
  ★ 칸: 우리 대장 표(silver.bld_hsprc · bld_expos_pubuse_area)가 쓰는 칸만. 값은 **글자 그대로**(load_hub 와 같은 원칙 — 숫자로 바꾸다 틀리지 않게).
  ★ 디스크: zip 을 다 풀지 않는다 — 500만 줄씩 골라 쓴 조각 파일을 BULK INSERT 하고 바로 지운다. 표는 PAGE 압축.
  ★ 표 hub.l<코드> = 그 달 한 벌(같은 달을 다시 넣으면 새 표로 갈아 끼움). hub.latest_done 에 무엇을 언제 넣었는지.
"""
import argparse, glob, io, json, os, re, sys, time, zipfile
import pymssql
from load_hub import env, 칸이름, SPEC, ROOT, ts

# 코드 → 넣을 칸(허브 칸 이름, 단위 괄호 뗀 것)
KEEP = {
  "0308": ["관리_건축물대장_PK", "대장_구분_코드", "대장_종류_코드", "대지_위치", "건물_명", "시군구_코드", "법정동_코드", "대지_구분_코드",
           "번", "지", "기준_일자", "주택가격", "생성_일자"],
  "0306": ["관리_건축물대장_PK", "대장_구분_코드", "대장_종류_코드", "대지_위치", "건물_명", "시군구_코드", "법정동_코드", "대지_구분_코드",
           "번", "지", "동_명", "호_명", "층_구분_코드", "층_번호", "전유_공용_구분_코드", "주_부속_구분_코드", "구조_코드", "구조_코드_명",
           "기타_구조", "주_용도_코드", "주_용도_코드_명", "기타_용도", "면적", "생성_일자"],
}
# ★ 10-25: 층별개요는 load_hub 의 버전 표(hub.t0304)를 못 쓴다 — 모든 칸이 같은 줄을 한 줄로 두는데(4.8만 줄), 층별개요의 그런 줄은 **진짜 다른 구획**이다
#   (API 적재도 면적을 합치고 seg_cnt 로 센다). 그래서 여기서 줄 그대로 한 벌 더.
KEEP["0304"] = ["관리_건축물대장_PK", "동_명", "건물_명", "층_구분_코드", "층_구분_코드_명", "층_번호", "층_번호_명", "구조_코드", "구조_코드_명", "기타_구조",
                "주_용도_코드", "주_용도_코드_명", "기타_용도", "면적", "주_부속_구분_코드", "주_부속_구분_코드_명", "면적_제외_여부", "생성_일자"]
KEEP["0302"] = ["관리_건축물대장_PK", "대지_위치", "세대_수", "생성_일자"]   # 시험용(작은 파일로 길 확인)
조각 = 5_000_000


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--code", required=True); ap.add_argument("--month")
    a = ap.parse_args()
    code = a.code; sp = SPEC[code]; cols = 칸이름(sp); keep = KEEP[code]
    idx = [cols.index(c) for c in keep]
    zs = sorted(z for z in glob.glob(os.path.join(ROOT, "2*", "*.zip")) if f"_{sp['분류']}_{sp['이름']}+(" in os.path.basename(z) or f"_{sp['분류']}_{sp['이름']}(" in os.path.basename(z))
    if a.month: zs = [z for z in zs if os.path.basename(os.path.dirname(z)) == a.month]
    if not zs: sys.exit("zip 없음")
    zpath = zs[-1]; month = os.path.basename(os.path.dirname(zpath))
    e = env()
    conn = pymssql.connect(server=e.get("DB_HOST", "127.0.0.1"), port=int(e.get("DB_PORT", 11433)), user=e.get("DB_USER", "sa"),
                           password=e.get("DB_PASSWORD", ""), database=e.get("DB_NAME", "Teomoony"), charset="UTF-8", autocommit=True, timeout=0)
    cur = conn.cursor()
    t0 = time.time()
    tb = f"hub.l{code}"; new = f"hub.l{code}_new"
    defs = ",\n  ".join(f"[{c}] {'VARCHAR(40)' if i == 0 else 'NVARCHAR(500)'} NULL" for i, c in enumerate(keep))
    cur.execute(f"IF SCHEMA_ID('hub') IS NULL EXEC('CREATE SCHEMA hub'); IF OBJECT_ID('{new}') IS NOT NULL DROP TABLE {new};")
    cur.execute(f"CREATE TABLE {new} (\n  {defs}\n) WITH (DATA_COMPRESSION = PAGE);")
    xdir = os.path.join(ROOT, "_x"); os.makedirs(xdir, exist_ok=True)
    txt = os.path.join(xdir, f"l{code}_{month}.txt"); inner = f"/bulk/hub/_x/l{code}_{month}.txt"
    n = 나쁨 = 0; buf = []
    def 붓기():
        nonlocal buf
        if not buf: return
        with open(txt, "w", encoding="utf-16", newline="") as f:   # BULK INSERT widechar(BOM) — load_hub 와 같은 이유
            f.write("".join(buf))
        cur.execute(f"""BULK INSERT {new} FROM '{inner}'
          WITH (DATAFILETYPE = 'widechar', FIELDTERMINATOR = '|', ROWTERMINATOR = '0x0a00', TABLOCK, BATCHSIZE = 500000, MAXERRORS = 0);""")
        os.remove(txt); buf = []
    print(f"[{ts()}] {code} {sp['분류']} {sp['이름']} {month} · 칸 {len(keep)}/{len(cols)}", flush=True)
    with zipfile.ZipFile(zpath) as z:
        names = [i for i in z.infolist() if not i.is_dir()]
        if len(names) != 1: raise RuntimeError(f"zip 안 파일 {len(names)}개")
        with z.open(names[0]) as src:
            rd = io.TextIOWrapper(src, encoding="utf-8", errors="strict", newline="")
            for line in rd:
                f = line.rstrip("\r\n").split("|")
                if len(f) != len(cols):
                    나쁨 += 1
                    if 나쁨 <= 5: print(f"  !! 칸 수 {len(f)} ≠ {len(cols)}: {line[:200]!r}", flush=True)
                    continue
                buf.append("|".join(f[i] for i in idx) + "\n"); n += 1
                if len(buf) >= 조각:
                    붓기(); print(f"  [{ts()}] {n:,}줄", flush=True)
    붓기()
    if 나쁨: raise RuntimeError(f"칸 수가 다른 줄 {나쁨:,} — 넣지 않고 멈춤(새 표는 {new} 에 남김)")
    cur.execute(f"CREATE INDEX ix_l{code}_pk ON {new} ([관리_건축물대장_PK]) WITH (DATA_COMPRESSION = PAGE);")
    cur.execute(f"BEGIN TRAN; IF OBJECT_ID('{tb}') IS NOT NULL DROP TABLE {tb}; EXEC sp_rename '{new}', 'l{code}'; COMMIT;")
    cur.execute("""IF OBJECT_ID('hub.latest_done') IS NULL CREATE TABLE hub.latest_done (code CHAR(4) NOT NULL, 월 CHAR(6) NOT NULL, 줄 BIGINT, 초 INT, 넣은때 DATETIME2(0) DEFAULT SYSDATETIME());
                   INSERT hub.latest_done (code, 월, 줄, 초) VALUES (%s, %s, %s, %s);""", (code, month, n, int(time.time() - t0)))
    print(f"  ✔ [{ts()}] {code} {sp['이름']} {month}: {n:,}줄 · {time.time()-t0:.0f}초", flush=True)


if __name__ == "__main__":
    main()
