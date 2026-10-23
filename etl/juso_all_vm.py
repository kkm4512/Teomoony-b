"""도로명주소 전체 받기 (2026-10-23) — VM 에서 돈다(DB 에 못 닿고 juso 에는 닿는다).
   py juso_all_vm.py get   : _export/juso_dongs.txt 의 법정동마다 끝 쪽까지 → _export/juso_all/<법정동>.json (다 받은 동은 건너뜀)
   py juso_all_vm.py sql   : 받은 것을 시군구마다 deploy/sql/p_ja_<시군구>.sql 로 (지우고 넣기 + _done)
   ★ admCd = 그 법정동인 것만. 건물관리번호마다 1줄. 키는 찍지 않는다."""
import io, json, os, sys, time, urllib.parse, urllib.request
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '_export', 'juso_all')
E = {}
for line in io.open(os.path.join(HERE, '..', '.env'), encoding='utf-8-sig'):
    line = line.strip()
    if line and not line.startswith('#') and '=' in line:
        k, v = line.split('=', 1); E[k.strip()] = v.strip().strip('"')
KEY = E.get('JUSO_KEY', '')
URL = 'https://business.juso.go.kr/addrlink/addrLinkApi.do'
WORKERS = 4
STOP = {'E0001', 'E0014', '-999'}   # 키 문제 · 막힘 → 멈춤

def ask(kw, page):
    d = {'confmKey': KEY, 'currentPage': page, 'countPerPage': 100, 'keyword': kw, 'resultType': 'json'}
    for k in range(5):
        try:
            j = json.loads(urllib.request.urlopen(URL + '?' + urllib.parse.urlencode(d), timeout=40).read().decode('utf-8'))
            return j['results']
        except Exception as ex:
            time.sleep(3 * (k + 1)); err = str(ex).replace(KEY, '***')
    raise RuntimeError('juso 실패: ' + err[:200])

def get(limit_s):
    os.makedirs(OUT, exist_ok=True)
    t0 = time.time(); n_dong = [0]; stop = [False]
    todo = [l.rstrip('\n').split('\t') for l in io.open(os.path.join(HERE, '_export', 'juso_dongs.txt'), encoding='utf-8') if l.strip()]
    todo = [x for x in todo if not os.path.exists(os.path.join(OUT, x[0] + '.json')) and not os.path.exists(os.path.join(OUT, x[0] + '.json.big'))]
    import threading
    lock = threading.Lock()
    def worker():
        while not stop[0] and time.time() - t0 <= limit_s:
            with lock:
                if not todo: return
                lawd, kw = todo.pop(0)
            if one(lawd, kw, stop, t0, limit_s): n_dong[0] += 1
    ts = [threading.Thread(target=worker) for _ in range(WORKERS)]
    [t.start() for t in ts]; [t.join() for t in ts]
    left = sum(1 for l in io.open(os.path.join(HERE, '_export', 'juso_dongs.txt'), encoding='utf-8') if l.strip() and not os.path.exists(os.path.join(OUT, l.split('\t')[0] + '.json')))
    print('이번', n_dong[0], '남은 동', left, round(time.time() - t0), 's')

def one(lawd, kw, stop, t0, limit_s):
        f = os.path.join(OUT, lawd + '.json')
        rows = {}; page = 1; total = None
        part = f + '.part'
        if os.path.exists(part):   # 지난번에 시간이 다 돼 멈춘 동 — 받은 쪽 다음부터
            d = json.load(io.open(part, encoding='utf-8')); rows = {x['bdMgtSn']: x for x in d['rows']}; page = d['next']
        while True:
            r = ask(kw, page); c = r['common']
            if c['errorCode'] != '0':
                if c['errorCode'] in STOP: print('멈춤', c['errorCode'], c['errorMessage']); stop[0] = True; return False
                print('오류', lawd, c['errorCode'], c['errorMessage']); total = None; break
            total = int(c['totalCount']); js = r.get('juso') or []
            for x in js:
                if x.get('admCd') == lawd and x.get('bdMgtSn'):
                    rows[x['bdMgtSn']] = {k: x.get(k) for k in ('admCd','rnMgtSn','rn','udrtYn','buldMnnm','buldSlno','mtYn','lnbrMnnm','lnbrSlno','bdMgtSn','bdNm','bdKdcd','detBdNmList','zipNo','roadAddr','jibunAddr')}
            if page * 100 >= total or not js: break
            if page >= 90:   # 검색 API 는 9,000줄까지만 준다(E0015) — 받은 것을 .big 에 두고 본번마다 다시 묻는다(big)
                json.dump({'lawd': lawd, 'kw': kw, 'total': total, 'rows': list(rows.values())}, io.open(f + '.big', 'w', encoding='utf-8'), ensure_ascii=False)
                if os.path.exists(part): os.remove(part)
                print('큰 동', lawd, kw, total, flush=True); return False
            page += 1
            if stop[0] or time.time() - t0 > limit_s + 15:   # 시간이 다 됨 — 받은 데까지 남기고 다음에 이어서
                json.dump({'next': page, 'rows': list(rows.values())}, io.open(part, 'w', encoding='utf-8'), ensure_ascii=False)
                print('이어받기', lawd, page, total, flush=True); return False
            time.sleep(0.05)
        if total is None: return False
        tmp = f + '.tmp'
        json.dump({'lawd': lawd, 'kw': kw, 'total': total, 'pages': page, 'rows': list(rows.values())}, io.open(tmp, 'w', encoding='utf-8'), ensure_ascii=False)
        os.replace(tmp, f)
        if os.path.exists(part): os.remove(part)
        print(lawd, kw, total, len(rows), flush=True)
        return True

def q(v, n=None):
    if v is None or v == '': return 'NULL'
    v = str(v)
    if n: v = v[:n]
    return "N'" + v.replace("'", "''") + "'"
def i(v):
    try: return str(int(v))
    except: return 'NULL'

def sql():
    by = {}
    for fn in sorted(os.listdir(OUT)):
        if fn.endswith('.json'):
            d = json.load(io.open(os.path.join(OUT, fn), encoding='utf-8')); by.setdefault(d['lawd'][:5], []).append(d)
    for sgg, ds in by.items():
        p = os.path.join(HERE, '..', 'deploy', 'sql', 'p_ja_' + sgg + '.sql')
        w = io.open(p, 'w', encoding='utf-8')
        w.write('SET NOCOUNT ON; SET XACT_ABORT ON;\nBEGIN TRAN;\n')
        for d in ds:
            w.write("DELETE FROM silver.juso_addr WHERE adm_cd = '%s';\n" % d['lawd'])
            rs = d['rows']
            for k in range(0, len(rs), 500):
                w.write('INSERT INTO silver.juso_addr (bd_mgt_sn, adm_cd, rn_mgt_sn, rn, udrt_yn, buld_mnnm, buld_slno, mt_yn, lnbr_mnnm, lnbr_slno, bd_nm, bd_kdcd, det_bd_nm, zip_no, road_addr, jibun_addr) VALUES\n')
                w.write(',\n'.join('(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)' % (
                    q(x['bdMgtSn']), q(x['admCd']), q(x['rnMgtSn']), q(x['rn']), q(x['udrtYn']), i(x['buldMnnm']), i(x['buldSlno']),
                    q(x['mtYn']), i(x['lnbrMnnm']), i(x['lnbrSlno']), q(x['bdNm'], 200), q(x['bdKdcd']), q(x['detBdNmList'], 1000),
                    q(x['zipNo']), q(x['roadAddr'], 400), q(x['jibunAddr'], 400)) for x in rs[k:k + 500]) + ';\n')
            w.write("DELETE FROM silver.juso_addr_done WHERE lawd_cd = '%s';\nINSERT INTO silver.juso_addr_done (lawd_cd, keyword, total_count, 받은줄, 다받음) VALUES ('%s', %s, %d, %d, 1);\n"
                    % (d['lawd'], d['lawd'], q(d['kw']), d['total'], len(d['rows'])))
        w.write('COMMIT;\nGO\nEXEC meta.usp_road_code_from_juso;\nGO\n')
        w.close(); print(sgg, len(ds), sum(len(d['rows']) for d in ds))

def big(limit_s):
    """9,000줄 넘는 법정동: 본번마다 '<동> <본번>' / '<동> 산<본번>' 으로 다시 묻는다. 받은 것 중 admCd · 산 · 본번이 맞는 것만."""
    import threading
    t0 = time.time()
    bon = {}
    for l in io.open(os.path.join(HERE, '_export', 'juso_bonbun.txt'), encoding='utf-8'):
        if l.strip():
            a, m, b = l.rstrip('\n').split('\t'); bon.setdefault(a, []).append((m, int(b)))
    for fn in sorted(os.listdir(OUT)):
        if not fn.endswith('.json.big'): continue
        d = json.load(io.open(os.path.join(OUT, fn), encoding='utf-8')); lawd = d['lawd']; kw = d['kw']
        bp = os.path.join(OUT, lawd + '.json.bigpart')
        st = json.load(io.open(bp, encoding='utf-8')) if os.path.exists(bp) else {'done': [], 'rows': d['rows']}
        rows = {x['bdMgtSn']: x for x in st['rows']}; done = set(map(tuple, st['done']))
        todo = [x for x in bon.get(lawd, []) if tuple(x) not in done]
        lock = threading.Lock()
        def worker():
            while time.time() - t0 <= limit_s:
                with lock:
                    if not todo: return
                    m, b = todo.pop(0)
                k2 = kw + ' ' + ('산' if m == '2' else '') + str(b); page = 1; got = {}
                while True:
                    r = ask(k2, page); c = r['common']
                    if c['errorCode'] != '0': print('오류', k2, c['errorCode']); got = None; break
                    js = r.get('juso') or []
                    for x in js:
                        if x.get('admCd') == lawd and x.get('bdMgtSn') and str(x.get('lnbrMnnm')) == str(b) and (x.get('mtYn') == '1') == (m == '2'):
                            got[x['bdMgtSn']] = {k: x.get(k) for k in ('admCd','rnMgtSn','rn','udrtYn','buldMnnm','buldSlno','mtYn','lnbrMnnm','lnbrSlno','bdMgtSn','bdNm','bdKdcd','detBdNmList','zipNo','roadAddr','jibunAddr')}
                    if page * 100 >= int(c['totalCount']) or not js or page >= 90: break
                    page += 1
                if got is None: continue
                with lock:
                    rows.update(got); done.add((m, b))
        ts = [threading.Thread(target=worker) for _ in range(WORKERS)]
        [t.start() for t in ts]; [t.join() for t in ts]
        if todo or len(done) < len(bon.get(lawd, [])):
            json.dump({'done': [list(x) for x in done], 'rows': list(rows.values())}, io.open(bp, 'w', encoding='utf-8'), ensure_ascii=False)
            print('이어받기', lawd, len(done), '/', len(bon.get(lawd, [])), flush=True); return
        f = os.path.join(OUT, lawd + '.json')
        json.dump({'lawd': lawd, 'kw': kw + ' (본번별)', 'total': d['total'], 'pages': -1, 'rows': list(rows.values())}, io.open(f, 'w', encoding='utf-8'), ensure_ascii=False)
        for x in (bp, os.path.join(OUT, fn)):
            if os.path.exists(x): os.remove(x)
        print('큰 동 끝', lawd, kw, d['total'], len(rows), flush=True)

if __name__ == '__main__':
    if sys.argv[1] == 'get': get(float(sys.argv[2]) if len(sys.argv) > 2 else 1e9)
    elif sys.argv[1] == 'big': big(float(sys.argv[2]) if len(sys.argv) > 2 else 1e9)
    else: sql()
