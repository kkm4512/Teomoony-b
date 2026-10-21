#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
runlog - 돌린 것을 파일로 남긴다

왜 필요한가
---------------------------------------------------------------
적재가 길어서(한 번에 몇 시간) 사람이 터미널 출력을 복사해 옮기는 것이
병목이 됐다. 결과가 **파일로 남아 있으면** 다음에 이어서 볼 때 물어볼 필요가
없다 — 무엇을 돌렸고, 무엇이 끝났고, 무엇이 깨졌는지 파일이 말한다.

남기는 것 두 가지
---------------------------------------------------------------
  logs/run_<시각>_<명령>.log   사람이 읽는 전문. 터미널에 나간 것 그대로
  logs/runs.jsonl              기계가 읽는 요약. 한 줄에 실행 하나

★ 둘 다 남기는 이유. 전문만 있으면 "지난 열흘 중 실패가 몇 번이었나" 를
  답하려고 매번 수백 KB 를 훑어야 한다. 요약만 있으면 **왜** 깨졌는지가 없다.
  요약으로 찾고 전문으로 확인한다.

★ 요약은 append 전용이다. 고쳐 쓰지 않는다 — 이력 자체가 정보다.
"""
import json, os, re, sys, time, traceback
from datetime import datetime

HERE     = os.path.dirname(os.path.abspath(__file__))
LOG_DIR  = os.path.join(HERE, "..", "logs")
JSONL    = os.path.join(LOG_DIR, "runs.jsonl")


class _Tee:
    """터미널과 파일에 동시에 쓴다. 사람이 보면서 파일에도 남는다."""
    def __init__(self, stream, fh, on_line=None):
        self.stream, self.fh, self.on_line = stream, fh, on_line
    def write(self, s):
        self.stream.write(s)
        if self.on_line:
            self.on_line(s)
        try:
            self.fh.write(s); self.fh.flush()
        except Exception:
            pass          # 파일 쓰기가 실패해도 **적재를 죽이지 않는다**
        return len(s)
    def flush(self):
        self.stream.flush()
        try: self.fh.flush()
        except Exception: pass
    def isatty(self):
        return getattr(self.stream, "isatty", lambda: False)()


class RunLog:
    def __init__(self, cmd, argv=None):
        os.makedirs(LOG_DIR, exist_ok=True)
        self.cmd     = cmd
        self.argv    = argv if argv is not None else sys.argv[1:]
        self.started = datetime.now()
        self.t0      = time.time()
        stamp        = self.started.strftime("%Y%m%d_%H%M%S")
        self.path    = os.path.join(LOG_DIR, f"run_{stamp}_{cmd}.log")
        self.events  = []
        self.counts  = {}
        self.note    = None
        self.totals  = {}        # 자식 출력에서 주운 지표
        self._buf    = ""
        self._fh = None

    # ---------- 수집 ----------
    def event(self, **kw):
        """단위 작업 하나의 결과. go 가 법정동 x op 마다 부른다."""
        kw["t"] = round(time.time() - self.t0, 1)
        self.events.append(kw)

    def count(self, key, n=1):
        self.counts[key] = self.counts.get(key, 0) + n

    def set_note(self, text):
        self.note = text

    def add_note(self, text):
        """덮지 않고 덧붙인다.

        ★ set_note 는 덮는다 (2026-10-17). 한도 소진·중단 사유처럼 **반드시
          사람에게 가야 하는 말**이 이미 들어 있을 수 있다. 뒤에 쓰는 쪽이
          앞의 말을 지우면, 정작 중요한 쪽이 사라진다."""
        self.note = (self.note + "\n" + text) if self.note else text

    # ★ 거친 단계(--steps)는 `units` 에 안 남는다 — 실패했을 때만 기록한다.
    #   그래서 카톡에 숫자가 하나도 안 담겼다: "적재 완료 · 51분" 이 전부였다.
    #   실제로는 "신규 22,896 · 호출실패 0" 이 로그에 있었는데 열어봐야 보였다.
    #   자식 출력이 Tee 를 지나가므로 **지나가는 길에 줍는다** (2026-10-17).
    _METRICS = (
        ("신규",     r"신규\s*([\d,]+)"),
        ("변경",     r"변경\s*([\d,]+)"),
        ("호출실패", r"호출실패\s*([\d,]+)"),
        ("데이터없음", r"데이터없음\s*([\d,]+)"),
    )

    def _scan(self, chunk):
        """자식이 찍은 요약 줄에서 숫자를 줍는다. 실패해도 조용히 넘어간다."""
        try:
            buf = self._buf + chunk
            *lines, self._buf = buf.split("\n")
            for ln in lines:
                if "신규" not in ln and "호출실패" not in ln:
                    continue
                for key, pat in self._METRICS:
                    m = re.search(pat, ln)
                    if m:
                        self.totals[key] = self.totals.get(key, 0) + \
                            int(m.group(1).replace(",", ""))
        except Exception:
            pass

    def _kakao_text(self, status, rec):
        """카톡 한 통에 들어갈 요약. **무엇을 했고 뭐가 깨졌는지**만."""
        mark = {"OK": "완료", "PARTIAL": "일부 실패",
                "INTERRUPTED": "중단됨", "ERROR": "오류"}.get(status, status)
        n_ok = sum(1 for e in self.events if e.get("ok"))
        n_no = len(self.events) - n_ok
        mins = (time.time() - self.t0) / 60
        head = f"[터무니] 적재 {mark} · {mins:.0f}분"
        body = f"\n명령: {' '.join(self.argv)}"
        if self.events:
            body += f"\n단위 {len(self.events)}건 (성공 {n_ok} / 실패 {n_no})"
        else:
            # ★ 빈손으로 끝난 패스도 **읽을 거리가 있어야 한다** (2026-10-17).
            #   "적재 완료 · 0분" 한 줄짜리 카톡이 왔다. 틀린 말은 아닌데
            #   아무것도 알려주지 않는다. 할 일이 없었다는 사실 자체가 소식이다.
            body += "\n할 일이 없었습니다"
        if self.totals:
            body += "\n" + " · ".join(
                f"{k} {v:,}" for k, v in self.totals.items() if v or k == "호출실패")
        if self.note:
            body += f"\n{self.note}"
        bad = [e for e in self.events if not e.get("ok")][:3]
        for e in bad:
            body += f"\n! {e.get('sgg')}/{e.get('bjdong')} {e.get('op')}"
        return head + body

    # ---------- 생애 ----------
    def __enter__(self):
        self._fh = open(self.path, "w", encoding="utf-8")
        self._fh.write(f"# {self.started:%Y-%m-%d %H:%M:%S}  "
                       f"py run_plan.py {' '.join(self.argv)}\n\n")
        sys.stdout = _Tee(sys.__stdout__, self._fh, self._scan)
        sys.stderr = _Tee(sys.__stderr__, self._fh)
        return self

    def __exit__(self, et, ev, tb):
        status = "OK"
        if et is KeyboardInterrupt:
            status = "INTERRUPTED"
        elif et is not None:
            status = "ERROR"
            self.set_note(f"{et.__name__}: {ev}")
            traceback.print_exception(et, ev, tb)      # Tee 를 통해 파일에도 간다

        failed = [e for e in self.events if not e.get("ok")]
        if status == "OK" and failed:
            status = "PARTIAL"

        rec = {
            "started":  self.started.isoformat(timespec="seconds"),
            "finished": datetime.now().isoformat(timespec="seconds"),
            "sec":      round(time.time() - self.t0, 1),
            "cmd":      self.cmd,
            "argv":     self.argv,
            "status":   status,
            "counts":   self.counts,
            "totals":   self.totals,
            "note":     self.note,
            "units":    self.events,
            "log":      os.path.basename(self.path),
        }
        try:
            with open(JSONL, "a", encoding="utf-8") as f:
                f.write(json.dumps(rec, ensure_ascii=False) + "\n")
        except Exception as e:
            sys.__stdout__.write(f"\n(요약 기록 실패: {e})\n")

        line = (f"\n[로그] {os.path.relpath(self.path, os.path.join(HERE, '..'))}"
                f"  status={status}")
        if failed:
            line += f"  실패 {len(failed)}건"
        print(line)

        # ★ 끝났으면 카톡으로 알린다 (2026-10-17).
        #   적재가 한두 시간씩 걸리는데 터미널을 지키고 있을 이유가 없다.
        #   설정 전이면 조용히 넘어간다 — 알림이 적재 기록을 방해하면 안 된다.
        if self.cmd == "go":
            try:
                import notify
                ok, why = notify.send(self._kakao_text(status, rec))
                print(f"[알림] {'보냄' if ok else '안 보냄 — ' + why}")
            except Exception as e:
                print(f"[알림] 실패 — {type(e).__name__}: {e}")

        sys.stdout, sys.stderr = sys.__stdout__, sys.__stderr__
        if self._fh:
            self._fh.close()
        return False          # 예외를 삼키지 않는다
