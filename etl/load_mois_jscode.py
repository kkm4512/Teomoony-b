# -*- coding: utf-8 -*-
"""load_mois_jscode - 행정안전부 「행정기관(행정동) 및 관할구역(법정동) 코드」 말소코드 포함판 → silver.mois_* (2026-10-31, deploy/sql/395)
  python load_mois_jscode.py <jscodeYYYYMMDD(말소코드포함).zip>

출처: 행정안전부 누리집 > 업무안내 > 주민등록·인감 > 「행정기관(행정동) 및 관할구역(법정동) 코드 변경내역 알림」 게시글 첨부
      (bbsId=BBSMSTR_000000000052) — 행정구역이 바뀔 때마다 새 글. 로그인 없음.
      말소코드포함 zip 안: KIKcd_B(법정동) · KIKcd_H(행정동) · KIKmix(행정동↔관할 법정동) — TEXT(cp949 고정폭) + 같은 내용 xlsx.
★ 고정폭 TEXT 를 바이트로 자른다(한글 2바이트). 첫 줄은 칸 제목. 칸 폭은 제목 줄에서 확인했다(2026-10-31):
    B   법정동코드 0-10 · 시도명 11-41 · 시군구명 42-72 · 읍면동명 73-103 · 동리명 104-134 · 생성일자 135-143 · 말소일자 144-152
    H   행정동코드 0-10 · 시도명 11-41 · 시군구명 42-72 · 읍면동명 73-103 · 생성일자 104-112 · 말소일자 113-121
    mix 행정동코드 0-10 · 시도명 · 시군구명 · 읍면동명 · 법정동코드 104-114 · 동리명 115-145 · 생성일자 146-154 · 말소일자 155-163
  제목 줄이 이 폭과 다르면 넣지 않고 멈춘다(형식이 바뀐 것 — 조용히 틀리지 않게).
★ 원문 그대로 넣는다(앞뒤 공백만 걷음 · 빈 칸 = NULL). 판(파일 날짜)마다 따로 쌓고, 같은 판을 다시 넣으면 그 판만 갈아 끼운다.
"""
import io, os, re, sys, time, zipfile
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from svc_publish import env
import pymssql

틀 = {
    "B":   (b"\xb9\xfd\xc1\xa4\xb5\xbf\xc4\xda\xb5\xe5", [(0, 10), (11, 41), (42, 72), (73, 103), (104, 134), (135, 143), (144, 152)],
            "silver.mois_bdong_code", ["법정동코드", "시도명", "시군구명", "읍면동명", "동리명", "생성일자", "말소일자"]),
    "H":   (b"\xc7\xe0\xc1\xa4\xb5\xbf\xc4\xda\xb5\xe5", [(0, 10), (11, 41), (42, 72), (73, 103), (104, 112), (113, 121)],
            "silver.mois_hdong_code", ["행정동코드", "시도명", "시군구명", "읍면동명", "생성일자", "말소일자"]),
    "mix": (b"\xc7\xe0\xc1\xa4\xb5\xbf\xc4\xda\xb5\xe5", [(0, 10), (11, 41), (42, 72), (73, 103), (104, 114), (115, 145), (146, 154), (155, 163)],
            "silver.mois_hdong_bdong", ["행정동코드", "시도명", "시군구명", "읍면동명", "법정동코드", "동리명", "생성일자", "말소일자"]),
}
# 제목 줄에서 칸 이름이 시작하는 바이트 위치 — 위 폭과 맞는지 확인용
제목칸 = {"B": ["법정동코드", "시도명", "시군구명", "읍면동명", "동리명", "생성일자", "말소일자"],
          "H": ["행정동코드", "시도명", "시군구명", "읍면동명", "생성일자", "말소일자"],
          "mix": ["행정동코드", "시도명", "시군구명", "읍면동명", "법정동코드", "동리명", "생성일자", "말소일자"]}


def 이름풀기(zi):
    n = zi.filename
    if not (zi.flag_bits & 0x800):
        try: n = n.encode("cp437").decode("cp949")
        except Exception: pass
    return n


def 읽기(raw, 종류):
    줄 = [l.rstrip(b"\r") for l in raw.split(b"\n") if l.strip()]
    머리 = 줄[0]; _, 폭, _, _ = 틀[종류]
    for (a, _), 칸 in zip(폭, 제목칸[종류]):
        if 머리[a:a + len(칸.encode("cp949"))].decode("cp949", "replace") != 칸:
            sys.exit(f"{종류}: 제목 줄 형식이 다릅니다 — '{칸}' 이 {a}바이트에 없음. 넣지 않음")
    out = []
    for l in 줄[1:]:
        r = [l[a:b].decode("cp949").strip() or None for a, b in 폭]
        if not re.fullmatch(r"\d{10}", r[0] or ""): sys.exit(f"{종류}: 코드가 아닌 줄 {l[:40]!r}")
        out.append(r)
    return out


def main():
    zp = sys.argv[1]; m = re.search(r"jscode(\d{8})", os.path.basename(zp))
    if not m: sys.exit("파일 이름에서 판(jscodeYYYYMMDD)을 못 찾음")
    판 = m.group(1); z = zipfile.ZipFile(zp); 자료 = {}
    for zi in z.infolist():
        n = 이름풀기(zi)
        if n.endswith("/") or n.lower().endswith(".xlsx"): continue
        b = os.path.basename(n)
        종류 = "B" if b.startswith("KIKcd_B") else "H" if b.startswith("KIKcd_H") else "mix" if b.startswith("KIKmix") else None
        if 종류: 자료[종류] = 읽기(z.read(zi), 종류)
    if set(자료) != {"B", "H", "mix"}: sys.exit(f"zip 안에 셋이 다 없음: {sorted(자료)}")
    if "말소" not in os.path.basename(zp) and not any(r[-1] for r in 자료["B"]): print("★ 말소 코드가 없는 판입니다(현행만)", flush=True)
    e = env()
    conn = pymssql.connect(server=e["DB_HOST"], port=int(e["DB_PORT"]), user=e["DB_USER"], password=e["DB_PASSWORD"],
                           database=e.get("DB_NAME", "Teomoony"), charset="UTF-8", autocommit=False)
    cur = conn.cursor()
    q = lambda v: "NULL" if v is None else "N'" + v.replace("'", "''") + "'"
    for 종류, rows in 자료.items():
        t0 = time.time(); _, _, 표, 칸 = 틀[종류]
        cur.execute(f"DELETE FROM {표} WHERE 판 = %s", (판,))
        for i in range(0, len(rows), 900):
            cur.execute(f"INSERT {표} (판, {', '.join(칸)}) VALUES " +
                        ",\n".join("(N'" + 판 + "'," + ",".join(q(v) for v in r) + ")" for r in rows[i:i + 900]))
        cur.execute(f"INSERT ops.mois_jscode_file (판, 종류, 줄, 말소줄, 파일) VALUES (%s, %s, %s, %s, %s)",
                    (판, 종류, len(rows), sum(1 for r in rows if r[-1]), os.path.basename(zp)))
        print(f"  {표} 판 {판}: {len(rows):,}줄 (말소 {sum(1 for r in rows if r[-1]):,}) · {time.time()-t0:.0f}초", flush=True)
    conn.commit(); conn.close()


if __name__ == "__main__":
    main()
