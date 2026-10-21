#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
load_kapt - 공동주택 단지정보(K-apt)를 silver.kapt_complex 에 적재

  py load_kapt.py --lawd 1129013800
  py load_kapt.py --sgg 11290           # 그 시군구의 법정동 전부
  py load_kapt.py --sgg 11110 --lawd 1111010100

왜 필요한가 (CONTEXT.md 4-13, 4-19)
  관리사무소 등록 기반이라 입주와 거의 동시에 올라온다. 건축물대장이 못
  따라오는 신축 구간을 메운다. 장위자이레디언트(2,840세대, 2025.3 사용승인)가
  대장·인허가·건물외곽선 어디에도 없는데 여기엔 있다.

주의
  * 버전 접미가 서비스마다 다르다. 목록은 ...List4, 기본/상세는 ...InfoV5.
    추측으로 맞히려다 두 번 헤맸다.
  * 응답이 XML 이 아니라 JSON 이다.
  * 단지 하나당 호출 3번(목록은 법정동 단위, 기본/상세는 단지 단위).
    일일 트래픽이 서비스당 5,000 이라 전국은 나눠 돌려야 한다.
  * PNU 는 meta.fn_make_pnu() 로만 만든다. 지번은 kaptAddr 에서 뽑는데,
    파싱이 실패하면 NULL 로 둔다. 조용히 틀린 PNU 를 만드느니 비워 둔다.
"""
import argparse, hashlib, os, re, sys, time
import requests
import pymssql

HERE = os.path.dirname(os.path.abspath(__file__))
ENV  = os.path.join(HERE, "..", ".env")
LIST = "https://apis.data.go.kr/1613000/AptListService4/getLegaldongAptList4"
BASS = "https://apis.data.go.kr/1613000/AptBasisInfoServiceV5/getAphusBassInfoV5"
DTL  = "https://apis.data.go.kr/1613000/AptBasisInfoServiceV5/getAphusDtlInfoV5"

# "서울특별시 성북구 장위동 62-1 장위자이레디언트" -> 산여부 / 본번 / 부번
#   법정동 이름(동/가/리) 바로 뒤의 첫 지번만 본다. 단지명에 섞인 숫자
#   ("장위 3단지")를 지번으로 오인하지 않기 위해서다.
#   ★ 이름 중간에 숫자가 들어가는 법정동이 있다: 보문동6가 / 종로1가 / 충무로3가.
#     [가-힣]+ 는 그 숫자를 못 넘어 매칭 자체가 실패했다(PNU NULL -> 뷰에서 사라짐).
#     성북구 보문파크뷰자이(거래 566건)가 이것 때문에 안 붙었다. 2026-10-15 수정.
JIBUN_RE = re.compile(r'[가-힣][가-힣\d]*(?:동|가|리)\s+(산\s*)?(\d+)(?:\s*-\s*(\d+))?(?!\d)')


def load_env(path):
    d = {}
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                d[k.strip()] = v.strip()
    return d


def get(url, key, params, retries=4):
    """data.go.kr 은 장애를 HTTP 200 으로 돌려준다.

      {"OpenAPI_ServiceResponse":{"cmmMsgHeader":{"errMsg":"HTTP_ERROR",...}}}

    이걸 성공으로 읽으면 item 이 없는 걸 "값 없음" 으로 착각하고 컬럼을 NULL 로
    덮어쓴다. 2026-10-16 포털 장애 때 성북구 148개 중 48개가 이렇게 비었다.
    에러 바디는 **실패다**. 재시도하고, 끝까지 실패하면 None 을 준다."""
    p = dict(params); p["serviceKey"] = key
    for a in range(retries):
        try:
            r = requests.get(url, params=p, timeout=40)
            if r.status_code == 200:
                try:
                    j = r.json()
                except Exception:
                    return None          # JSON 이 아니면 포기 (재시도해도 같다)
                if isinstance(j, dict) and "OpenAPI_ServiceResponse" in j:
                    h = (j["OpenAPI_ServiceResponse"] or {}).get("cmmMsgHeader") or {}
                    msg = h.get("errMsg") or "?"
                    if a == retries - 1:
                        print(f"      !! 포털 오류 {msg} ({h.get('returnReasonCode')}) "
                              f"{params}", flush=True)
                    time.sleep(1.5 * (a + 1))
                    continue
                return j
        except Exception:
            pass
        time.sleep(1.2 * (a + 1))
    return None


def parse_jibun(addr):
    """kaptAddr -> (plat_gb_cd, bun, ji). 못 읽으면 (None, None, None)."""
    if not addr:
        return (None, None, None)
    m = JIBUN_RE.search(addr)
    if not m:
        return (None, None, None)
    san, bun, ji = m.group(1), m.group(2), m.group(3)
    return ("1" if san else "0", bun.zfill(4), (ji or "0").zfill(4))


def num(v, f=float):
    """숫자로. 못 읽으면 None.

    ★ f=int 로 쓸 때 조심할 것. K-apt 는 정수여야 할 값을 **float 로 준다**
      (kaptdaCnt = 1562.0). int("1562.0") 는 ValueError 라 except 가 삼키고
      조용히 None 이 된다. 2026-10-16 에 hhld_cnt 가 148건 전부 NULL 로
      들어간 원인이다. 정수는 num() 대신 **inum() 을 쓴다.**
    """
    try:
        s = str(v).strip().replace(",", "")
        return f(s) if s not in ("", "None") else None
    except Exception:
        return None


def inum(v):
    """정수로. '1562.0' 도, 1562 도, '1,562' 도 1562 이 된다."""
    try:
        s = str(v).strip().replace(",", "")
        if s in ("", "None", "-"):
            return None
        return int(float(s))
    except Exception:
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sgg", nargs="*", help="시군구코드 5자리")
    ap.add_argument("--lawd", nargs="*", help="법정동코드 10자리")
    ap.add_argument("--sleep", type=float, default=0.15)
    args = ap.parse_args()

    env = load_env(ENV)
    key = env.get("DATA_GO_KR_KEY", "").strip()
    if not key:
        sys.exit(".env 의 DATA_GO_KR_KEY 가 비어 있습니다")

    conn = pymssql.connect(server=env.get("DB_HOST", "127.0.0.1"),
                           port=int(env.get("DB_PORT", 11433)),
                           user=env.get("DB_USER", "sa"),
                           password=env.get("DB_PASSWORD", ""),
                           database=env.get("DB_NAME", "Teomoony"),
                           charset="UTF-8", autocommit=False)
    cur = conn.cursor()

    lawds = list(args.lawd or [])
    for sgg in (args.sgg or []):
        cur.execute("SELECT lawd_cd FROM meta.lawd_code WHERE sgg_cd=%s ORDER BY lawd_cd", (sgg,))
        lawds += [r[0] for r in cur.fetchall()]
    lawds = sorted(set(lawds))
    if not lawds:
        sys.exit("대상 법정동이 없습니다. --lawd 또는 --sgg 를 주세요.")
    print(f"대상 법정동 {len(lawds)}개")

    total_new = no_pnu = skip_dtl = 0
    for lawd in lawds:
        j = get(LIST, key, {"bjdCode": lawd, "numOfRows": 500, "pageNo": 1})
        items = (((j or {}).get("response") or {}).get("body") or {}).get("items") or []
        if isinstance(items, dict):
            items = items.get("item") or []
        if not items:
            continue
        print(f"\n  {lawd}  단지 {len(items)}개")
        n = 0
        for it in items:
            code = (it.get("kaptCode") or "").strip()
            if not code:
                continue
            jb = get(BASS, key, {"kaptCode": code}) or {}
            b = (((jb.get("response") or {}).get("body") or {}).get("item")) or {}
            jd = get(DTL, key, {"kaptCode": code})
            d = (((jd or {}).get("response") or {}).get("body") or {}).get("item") or {}
            if not b:
                continue
            # 상세가 실패했으면 이 단지는 건너뛴다.
            #   d={} 로 진행하면 row_hash 가 바뀌어 **상세 컬럼 전체가 NULL 인
            #   새 행으로 갈아친다.** 멀쩡한 값을 장애가 지우는 길이다.
            if jd is None:
                skip_dtl += 1
                continue

            addr = (b.get("kaptAddr") or "").strip()
            gb, bun, ji = parse_jibun(addr)
            bjd = (b.get("bjdCode") or it.get("bjdCode") or lawd).strip()

            vals = dict(
                kapt_code=code, kapt_name=(b.get("kaptName") or it.get("kaptName")),
                bjd_code=bjd, plat_gb_cd=gb, bun=bun, ji=ji,
                kapt_addr=addr, doro_juso=b.get("doroJuso"),
                # hoCnt 는 **호수**, kaptdaCnt 가 **세대수**다. 보통 같지만 다르다.
                #   래미안퍼스트하이 호수 1,568 / 세대수 1,562 (대장 세대수와 일치)
                # 세대당 관리비의 분모가 이것이라 틀리면 전 단지가 조용히 틀린다.
                ho_cnt=inum(b.get("hoCnt")),
                hhld_cnt=inum(b.get("kaptdaCnt")),
                dong_cnt=inum(b.get("kaptDongCnt")),
                kapt_usedate=(b.get("kaptUsedate") or None),
                kapt_tarea=num(b.get("kaptTarea")), kapt_marea=num(b.get("kaptMarea")),
                priv_area=num(b.get("privArea")),
                top_floor=inum(b.get("kaptTopFloor")), base_floor=inum(b.get("kaptBaseFloor")),
                # 주차는 상세의 지상+지하다. kaptdaCnt 가 아니다 — 그건 세대수이고,
                # 2026-10-16 까지 이 자리에 세대수가 들어가 화면이 주차로 보여줬다.
                parking_cnt=(lambda g, u: None if g is None and u is None
                             else (g or 0) + (u or 0))(
                    inum(d.get("kaptdPcnt")), inum(d.get("kaptdPcntu"))),
                code_apt_nm=b.get("codeAptNm"), code_sale_nm=b.get("codeSaleNm"),
                code_heat_nm=b.get("codeHeatNm"), code_hall_nm=b.get("codeHallNm"),
                code_mgr_nm=b.get("codeMgrNm"),
                bcompany=b.get("kaptBcompany"), acompany=b.get("kaptAcompany"),
                mgr_cnt=inum(d.get("kaptMgrCnt")),
                wtime_bus=d.get("kaptdWtimebus"), wtime_sub=d.get("kaptdWtimesub"),
                subway_line=d.get("subwayLine"), subway_station=d.get("subwayStation"),
                use_yn=d.get("useYn"),
                # ---- 상세 항목 (21_kapt_link.sql) ----
                # 전기차 충전기는 groundElChargerCnt / undergroundElChargerCnt 다.
                # kaptdEcnt 가 아니다 — 그쪽은 **승강기 대수**다
                # (래미안퍼스트하이 40대 / 16동 32층). 전기 관련이 아니다.
                # 뜻이 분명한 필드만 가져온다. 애매한 것은 안 가져오는 편이 낫다.
                el_charger_ground=inum(d.get("groundElChargerCnt")),
                el_charger_under=inum(d.get("undergroundElChargerCnt")),
                parking_ground=inum(d.get("kaptdPcnt")),
                parking_under=inum(d.get("kaptdPcntu")),
                cctv_cnt=inum(d.get("kaptdCccnt")),
                sec_cnt=inum(d.get("kaptdScnt")),
                clean_cnt=inum(d.get("kaptdClcnt")),
                sec_company=d.get("kaptdSecCom"), clean_company=d.get("kaptCcompany"),
                code_sec_nm=d.get("codeSec"), code_clean_nm=d.get("codeClean"),
                code_garbage_nm=d.get("codeGarbage"), code_disinf_nm=d.get("codeDisinf"),
                code_elev_nm=d.get("codeElev"),
                welfare_facility=d.get("welfareFacility"),
                convenient_facility=d.get("convenientFacility"),
                education_facility=d.get("educationFacility"),
            )

            # PNU 는 DB 함수로만 만든다
            pnu = None
            if bjd and len(bjd) == 10 and bun:
                cur.execute("SELECT meta.fn_make_pnu(%s,%s,%s,%s,%s)",
                            (bjd[:5], bjd[5:], gb, bun, ji))
                pnu = cur.fetchone()[0]
            vals["pnu"] = pnu
            if not pnu:
                no_pnu += 1

            rh = hashlib.sha256("\x1f".join(
                str(vals[k]) for k in sorted(vals)).encode("utf-8")).digest()
            cur.execute("""UPDATE silver.kapt_complex
                              SET is_current=0, valid_to=SYSDATETIME()
                            WHERE is_current=1 AND kapt_code=%s AND row_hash<>%s""", (code, rh))
            cols = list(vals.keys())
            cur.execute(
                f"IF NOT EXISTS (SELECT 1 FROM silver.kapt_complex "
                f"WHERE is_current=1 AND kapt_code=%s) "
                f"INSERT INTO silver.kapt_complex ({', '.join(cols)}, row_hash) "
                f"VALUES ({', '.join(['%s']*len(cols))}, %s)",
                (code,) + tuple(vals[c] for c in cols) + (rh,))
            n += 1
            time.sleep(args.sleep)
        conn.commit()
        total_new += n
        print(f"    -> {n} 적재")

    cur.execute("SELECT COUNT(*), SUM(CASE WHEN pnu IS NULL THEN 1 ELSE 0 END) "
                "FROM silver.kapt_complex WHERE is_current=1")
    tot, nullpnu = cur.fetchone()
    print(f"\nK-apt 단지 총 {tot:,}건 | PNU 없음 {nullpnu or 0:,}건")
    if skip_dtl:
        print(f"상세 응답 실패로 건너뛴 단지 {skip_dtl:,}건 — 포털 장애일 수 있다. "
              f"나중에 같은 명령을 다시 돌리면 그 단지만 채워진다.")
    if nullpnu:
        cur.execute("""SELECT TOP 5 kapt_code, kapt_name, kapt_addr
                         FROM silver.kapt_complex
                        WHERE is_current=1 AND pnu IS NULL""")
        print("  지번을 못 읽은 예:")
        for r in cur.fetchall():
            print(f"    {r[0]}  {r[1]}  |  {r[2]}")

    # ★ 2026-10-21: K-apt 를 새로 넣었으면 **단지 ↔ K-apt 연결 표**를 다시 굳힌다(280).
    #   상세(관리비)와 지도 신축 마커가 둘 다 이 표를 본다 — 안 하면 새 K-apt 가 화면에 안 붙는다.
    cur.execute("EXEC gold.usp_refresh_complex_kapt")
    r = cur.fetchone()
    conn.commit()
    print(f"\n단지 ↔ K-apt 연결 다시 굳힘: {r[0]:,}개 ({r[1]}초)")
    conn.close()


if __name__ == "__main__":
    main()
