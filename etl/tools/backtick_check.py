#!/usr/bin/env python3
"""SQL 템플릿 리터럴(.query(`...`)) 안의 백틱을 찾는다.

★ 왜: 2026-10-21 하루에 **네 번** 같은 실수를 했다. SQL 주석에 `칸이름` 처럼
  백틱을 쓰면 템플릿 문자열이 거기서 끊겨 'SyntaxError: missing ) after argument
  list' 가 난다. node --check 가 잡아 주지만 **어디인지는 안 알려준다.**
  이 검사기는 줄 번호와 그 줄을 찍는다.

쓰기: python3 etl/tools/backtick_check.py <파일...>
"""
import re, sys

def check(path):
    s = open(path, encoding='utf-8').read()
    나쁨 = []
    for m in re.finditer(r"\.query\(`", s):
        i = m.end()
        j = s.find('`', i)                     # 템플릿의 끝(첫 백틱)
        if j < 0:
            나쁨.append((s[:i].count('\n') + 1, '(닫는 백틱을 못 찾음)')); continue
        본문 = s[i:j]
        # 주석 안에 백틱이 있었다면 본문이 **너무 일찍** 끝났을 수 있다.
        # 끝난 자리 뒤가 SQL 처럼 이어지면 의심.
        뒤 = s[j+1:j+40]
        if not re.match(r"\s*\)|\s*,|\s*;", 뒤):
            나쁨.append((s[:j].count('\n') + 1, s[max(0, j-70):j+30].replace('\n', ' ⏎ ')))
    for 줄, 글 in 나쁨:
        print(f"{path}:{줄}: SQL 템플릿이 여기서 끊겼다 — 백틱 확인  … {글}")
    return len(나쁨)

if __name__ == '__main__':
    n = sum(check(p) for p in sys.argv[1:])
    print('의심 0건' if not n else f'의심 {n}건')
    sys.exit(1 if n else 0)
