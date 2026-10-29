# 이 PC 의 공유기 쪽 주소(LAN IP)로 5173 · 11433 · 15432 · 16379 에 붙어 본다 — 막혔으면 '안 열림' 이 맞다(2026-10-29 보안)
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.connect(("8.8.8.8", 80)); ip = s.getsockname()[0]; s.close()
print("LAN 주소", ip.rsplit(".", 1)[0] + ".x")
for port in (5173, 11433, 15432, 16379):
    for host, nm in ((ip, "LAN"), ("127.0.0.1", "PC 안")):
        c = socket.socket(); c.settimeout(2)
        try: c.connect((host, port)); r = "열림"
        except Exception as e: r = "안 열림"
        finally: c.close()
        print(f"  {port} {nm}: {r}")
