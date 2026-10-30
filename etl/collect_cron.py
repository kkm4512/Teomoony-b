# -*- coding: utf-8 -*-
"""collect_cron - 수집 일정(ops.collect_schedule)대로 작업을 걸고, 돌았는지 · 안 돌았으면 왜인지 ops.collect_run 에 적는다 (2026-10-28)
  사장님 "스케줄 적용하고, 스케줄이 도는 것들을 로그 — 돌았나 안 돌았나, 안 돌았으면 어떤 이유로".
  svc_cron.py(매시 발행 · 매칭 테이블)를 대신한다 — 그 둘도 일정표의 한 줄이다.

  ★ 상태: 놓음(큐에 올림) → 도는중(로그가 생김) → 성공(종료코드 0) / 실패(그 밖) / 건너뜀(종료코드 3 = '출처에 새 것 없음' 등 · 겹침 · 디스크)
          못돎 = 예정 시각에 이 프로그램이 꺼져 있었다(PC 꺼짐 · 감시기 꺼짐) — 다시 켜질 때 사이를 보고 적는다.
  ★ 작업 실행기(_job_runner)는 건드리지 않는다 — 큐에 .job 을 놓고, 끝나면 done 으로 옮겨진 것과 로그 끝 줄('종료코드 N')을 읽는다.
  ★ 주기 글: hourly :05 · every 6h :35 · daily 04:10 · weekly mon 03:30 · monthly 3 02:00 · quarterly 1,4,7,10 5 03:00 · yearly 06-05 03:00
  py collect_cron.py            계속 돈다(뒷줄 -bg)
  py collect_cron.py --once     한 바퀴만(시험)"""
import datetime as D, glob, json, os, re, shutil, sys, time, traceback
from svc_publish import env, ms_conn
HERE = os.path.dirname(os.path.abspath(__file__))
Q = os.path.join(HERE, "_queue"); DONE = os.path.join(Q, "done"); LOGS = os.path.join(HERE, "..", "logs")
STATE = os.path.join(Q, "_cron_state.json")
요일 = {"mon": 0, "tue": 1, "wed": 2, "thu": 3, "fri": 4, "sat": 5, "sun": 6}

def 예정들(주기, a, b):
    """(a, b] 사이에 든 예정 시각들"""
    s = 주기.strip().lower(); out = []
    def hm(x): h, m = x.split(":"); return int(h), int(m)
    t = a.replace(second=0, microsecond=0)
    if s.startswith("hourly"):
        m = int(s.split(":")[1]); c = t.replace(minute=m) - D.timedelta(hours=1)
        while c <= b:
            if c > a: out.append(c)
            c += D.timedelta(hours=1)
        return out
    m_every = re.match(r"every (\d+)h :(\d+)", s)
    day = a.date() - D.timedelta(days=1)
    while day <= b.date():
        cands = []
        if m_every:
            k, mm = int(m_every.group(1)), int(m_every.group(2))
            cands = [D.datetime.combine(day, D.time(h, mm)) for h in range(0, 24, k)]
        elif s.startswith("daily"):
            h, mm = hm(s.split()[1]); cands = [D.datetime.combine(day, D.time(h, mm))]
        elif s.startswith("weekly"):
            _, w, x = s.split(); h, mm = hm(x)
            if day.weekday() == 요일[w]: cands = [D.datetime.combine(day, D.time(h, mm))]
        elif s.startswith("monthly"):
            _, dd, x = s.split(); h, mm = hm(x)
            if day.day == int(dd): cands = [D.datetime.combine(day, D.time(h, mm))]
        elif s.startswith("quarterly"):
            _, ms_, dd, x = s.split(); h, mm = hm(x)
            if day.month in {int(v) for v in ms_.split(",")} and day.day == int(dd): cands = [D.datetime.combine(day, D.time(h, mm))]
        elif s.startswith("yearly"):
            _, md, x = s.split(); h, mm = hm(x); mo, dd = md.split("-")
            if (day.month, day.day) == (int(mo), int(dd)): cands = [D.datetime.combine(day, D.time(h, mm))]
        out += [c for c in cands if a < c <= b]
        day += D.timedelta(days=1)
    return sorted(out)

def C():
    c = ms_conn(env()); return c.cursor()
def 쓰기(sql, args=()):
    cur = C(); cur.execute(sql, args)
    try: return cur.fetchone()
    except Exception: return None
def 기록(sch, 예정, 상태, 이유=None, 놓음=None):
    r = 쓰기("""INSERT INTO ops.collect_run (schedule_id, 이름, 작업, 예정, 놓음, 상태, 이유) OUTPUT inserted.run_id
                VALUES (%s, %s, %s, %s, %s, %s, %s)""", (sch["id"], sch["이름"], sch["작업"], 예정, 놓음, 상태, 이유))
    return r[0] if r else None
def C드라이브(): return shutil.disk_usage("C:\\").free / 2**30
# 같은 일을 하는 다른 이름의 작업(손으로 건 것 · 옛 이름)도 겹침으로 본다
겹침 = {"cl-svc-hourly-par": ("sp-hourly",), "nm-build-par": ("nm-build",), "cl-rtms-recent-par": ("rm-rematch", "rn-rtms", "rtms")}
def 큐에있음(job):
    if os.path.exists(os.path.join(Q, job + ".job")): return True
    return any(f.endswith(".job") and f.startswith(p) for f in os.listdir(Q) for p in 겹침.get(job, ()))

def 일정읽기():
    cur = C(); cur.execute("SELECT schedule_id, 이름, 자료, 작업, 주기, 못돎이면 FROM ops.collect_schedule WHERE 켜짐 = 1")
    return [dict(zip(("id", "이름", "자료", "작업", "주기", "못돎이면"), r)) for r in cur.fetchall()]

def 상태읽기():
    try: return json.load(open(STATE, encoding="utf-8"))
    except Exception: return {}
def 상태쓰기(st):
    tmp = STATE + ".tmp"; json.dump(st, open(tmp, "w", encoding="utf-8"), ensure_ascii=False); os.replace(tmp, STATE)

def 걸기(sch, 예정, 놓을때):
    job = sch["작업"]
    if 큐에있음(job): return 기록(sch, 예정, "건너뜀", "이전 실행이 아직 큐에 있음(도는 중이거나 기다리는 중) — 겹쳐 걸지 않음")
    free = C드라이브()
    if free < 10: return 기록(sch, 예정, "건너뜀", f"C 드라이브 {free:.1f}GB — 10GB 아래라 무거운 수집을 안 건다")
    open(os.path.join(Q, job + ".job"), "w", encoding="utf-8").write(f"{놓을때:%Y-%m-%d %H:%M:%S} collect_cron · {sch['이름']} · 예정 {예정:%m-%d %H:%M}\n")
    return 기록(sch, 예정, "놓음", None, 놓을때)

def 로그찾기(job, 이후):
    best = None
    for p in glob.glob(os.path.join(LOGS, f"job_*_{job}.log")):
        m = re.search(r"job_(\d{8}_\d{6})_", os.path.basename(p))
        if not m: continue
        t = D.datetime.strptime(m.group(1), "%Y%m%d_%H%M%S")
        if t >= 이후 - D.timedelta(seconds=5) and (best is None or t < best[0]): best = (t, p)
    return best

def 따라가기():
    """놓음 · 도는중 인 기록을 실제와 맞춘다"""
    cur = C(); cur.execute("SELECT run_id, 작업, 놓음, 상태 FROM ops.collect_run WHERE 상태 IN (N'놓음', N'도는중') AND 놓음 IS NOT NULL")
    for run_id, job, 놓음, 상태 in cur.fetchall():
        lg = 로그찾기(job, 놓음)
        if lg:
            t0, p = lg
            txt = open(p, encoding="utf-8", errors="replace").read()
            m = re.search(r"끝 (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\s+종료코드 (-?\d+)", txt)
            if m and not os.path.exists(os.path.join(Q, job + ".job")):
                rc = int(m.group(2)); 끝 = D.datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S")
                # 10-31: 창을 닫아 강제 종료된 작업의 종료코드는 3221225786(0xC000013A) — ops.collect_run.종료코드(INT)를 넘어 UPDATE 가 넘침 오류를 내고
                #   그 뒤 바퀴가 통째로 실패했다(10-30 20:29 ~ 10-31 07:50). 같은 32비트 값을 부호 있는 수로 적는다(-1073741510).
                if rc > 2147483647: rc -= 4294967296
                st = "성공" if rc == 0 else "건너뜀" if rc == 3 else "실패"
                이유 = None
                if rc != 0:
                    tail = [l.strip() for l in txt.splitlines() if l.strip() and not l.strip().startswith("끝 ")][-4:]
                    이유 = (("출처에 새 것 없음 · " if rc == 3 else "") + " / ".join(tail))[:600]
                쓰기("""UPDATE ops.collect_run SET 상태 = %s, 시작 = %s, 끝 = %s, 종료코드 = %s, 초 = %s, 로그 = %s, 이유 = COALESCE(%s, 이유)
                        WHERE run_id = %s""", (st, t0, 끝, rc, int((끝 - t0).total_seconds()), os.path.basename(p), 이유, run_id))
            elif 상태 != "도는중":
                쓰기("UPDATE ops.collect_run SET 상태 = N'도는중', 시작 = %s, 로그 = %s WHERE run_id = %s", (t0, os.path.basename(p), run_id))
        elif not os.path.exists(os.path.join(Q, job + ".job")):
            if D.datetime.now() - 놓음 > D.timedelta(minutes=3):
                쓰기("UPDATE ops.collect_run SET 상태 = N'실패', 이유 = N'큐에서 사라졌는데 로그가 없음(거절됐을 수 있음 — _queue/rejected 확인)' WHERE run_id = %s", (run_id,))
        elif D.datetime.now() - 놓음 > D.timedelta(minutes=30):
            쓰기("UPDATE ops.collect_run SET 이유 = N'30분 넘게 큐에서 기다리는 중(병렬 줄이 꽉 참)' WHERE run_id = %s AND 이유 IS NULL", (run_id,))

def 한바퀴(st):
    지금 = D.datetime.now().replace(microsecond=0)
    last = D.datetime.strptime(st["last"], "%Y-%m-%d %H:%M:%S") if st.get("last") else 지금 - D.timedelta(seconds=60)
    끊김 = (지금 - last) > D.timedelta(minutes=5)
    for sch in 일정읽기():
        dues = 예정들(sch["주기"], last, 지금)
        if not dues: continue
        if 끊김:
            지난 = [d for d in dues if d < 지금 - D.timedelta(minutes=2)]
            for d in 지난:
                기록(sch, d, "못돎", f"예정 시각에 수집 일정 프로그램이 꺼져 있었음(마지막 확인 {last:%m-%d %H:%M} → 다시 켜짐 {지금:%m-%d %H:%M}) — PC 꺼짐 또는 감시기 꺼짐")
            if 지난 and sch["못돎이면"] == "once":
                걸기(sch, 지난[-1], 지금)
            for d in dues:
                if d not in 지난: 걸기(sch, d, 지금)
        else:
            for d in dues: 걸기(sch, d, 지금)
    따라가기()
    for sch in 일정읽기():   # 다음 예정 · 확인 시각(화면 '수집 현황' 이 읽는다)
        nx = 예정들(sch["주기"], 지금, 지금 + D.timedelta(days=400))
        쓰기("UPDATE ops.collect_schedule SET 다음 = %s, 확인 = %s WHERE schedule_id = %s", (nx[0] if nx else None, 지금, sch["id"]))
    st["last"] = f"{지금:%Y-%m-%d %H:%M:%S}"; 상태쓰기(st)

if __name__ == "__main__":
    st = 상태읽기()
    print(f"collect_cron 시작 — 지난 확인 {st.get('last', '없음')}", flush=True)
    while True:
        try: 한바퀴(st)
        except Exception as e:
            print(f"[{D.datetime.now():%m-%d %H:%M}] 바퀴 실패: {e}", flush=True); traceback.print_exc()
        if "--once" in sys.argv: break
        time.sleep(30)
