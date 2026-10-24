# -*- coding: utf-8 -*-
"""_rate - 적재기 공용 **속도 맞추개**(AIMD)  2026-10-24

  사장님 "운영키 · 적재할 때 스레드를 최대한". 스레드를 많이 띄우면 API 가 **초당 요청 수**로 막는다
  (VWorld NED 실측: 초당 80 으로 250건쯤 보내면 수십 초 동안 502 · 연결 끊김). 스레드 수가 아니라 속도가 문제라,
  스레드는 넉넉히 두고 요청 **시작 간격**을 모든 스레드가 같이 맞춘다.
    · 성공 200번마다 초당 +1(상한 최대).  · 막히면(429 · 5xx · 끊김) 절반으로 + 10초 쉼(이미 쉬는 중이면 겹쳐 세지 않음).
  쓰는 법: 조절 = 조절기(8, 40);  조절.기다림() → 요청 → 조절.성공() / 조절.실패()
"""
import threading, time


class 조절기:
    def __init__(self, rps=8.0, 최대=40.0, 쉼초=10.0):
        self.lock = threading.Lock(); self.rps = float(rps); self.최대 = float(최대); self.쉼초 = 쉼초
        self.다음 = 0.0; self.쉬는끝 = 0.0; self.연속성공 = 0; self.쉼횟수 = 0

    def 기다림(self):
        while True:
            with self.lock:
                지금 = time.time()
                if 지금 < self.쉬는끝:
                    w, 자리 = self.쉬는끝 - 지금, False
                else:
                    시작 = max(지금, self.다음); self.다음 = 시작 + 1.0 / self.rps
                    w, 자리 = 시작 - 지금, True
            if w > 0:
                time.sleep(w)
            if 자리:
                return

    def 실패(self):
        with self.lock:
            if time.time() < self.쉬는끝:
                return
            self.rps = max(1.0, self.rps / 2); self.쉬는끝 = time.time() + self.쉼초
            self.연속성공 = 0; self.쉼횟수 += 1

    def 성공(self):
        with self.lock:
            self.연속성공 += 1
            if self.연속성공 >= 500:   # 올리는 건 천천히 — 막히면 수십 초를 잃는다
                self.rps = min(self.최대, self.rps + 1.0); self.연속성공 = 0
