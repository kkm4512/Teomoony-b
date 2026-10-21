#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""진행 상황과 예상 종료 시각.

적재가 길다. "지금 어디쯤이고 언제 끝나는가" 를 모르면 기다릴지 끊을지
판단할 수 없다.

남은 시간은 **지금까지의 평균 속도로만** 추정한다. 법정동마다 건수가 수십 배
차이나므로(종로구에서 3건짜리와 12,204건짜리가 같이 있다) 정확하지 않다.
그래서 '약' 을 붙이고, 초 단위로 쪼개 보여주지 않는다.
없는 정밀도를 있는 것처럼 보이면 안 된다.
"""
import time
from datetime import datetime, timedelta


def hhmm(sec):
    sec = int(max(sec, 0))
    h, m, s = sec // 3600, (sec % 3600) // 60, sec % 60
    if h: return f"{h}시간 {m}분"
    if m: return f"{m}분 {s}초"
    return f"{s}초"


def now():
    return datetime.now().strftime("%H:%M:%S")


def at(sec_from_now):
    return (datetime.now() + timedelta(seconds=max(sec_from_now, 0))).strftime("%H:%M")


class Step:
    """단계 하나. 시작 시각과 소요를 찍는다. 끝을 모르는 작업용."""

    def __init__(self, label):
        self.label = label
        self.t0 = time.time()
        print(f"[{now()}] ▶ {label}", flush=True)

    def done(self, note=""):
        el = time.time() - self.t0
        print(f"[{now()}] ✔ {self.label} — {hhmm(el)}" + (f" · {note}" if note else ""),
              flush=True)
        return el


class Progress:
    """N개짜리 반복. tick() 할 때마다 남은 시간을 다시 추정한다."""

    def __init__(self, total, label="진행"):
        self.total = max(int(total), 1)
        self.label = label
        self.i = 0
        self.t0 = time.time()
        print(f"[{now()}] {label} 시작 · 대상 {self.total:,}개", flush=True)

    def tick(self, note=""):
        self.i += 1
        el = time.time() - self.t0
        left = (el / self.i) * (self.total - self.i)
        tail = "" if self.i >= self.total else f"  남은 시간 약 {hhmm(left)} · 예상 종료 {at(left)}"
        print(f"  [{self.i}/{self.total}] {100.0*self.i/self.total:5.1f}%  {note}{tail}",
              flush=True)

    def done(self, note=""):
        el = time.time() - self.t0
        print(f"[{now()}] {self.label} 완료 — {hhmm(el)}" + (f" · {note}" if note else ""),
              flush=True)
        return el
