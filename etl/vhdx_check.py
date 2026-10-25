# -*- coding: utf-8 -*-
"""vhdx_check - Docker 데이터 디스크(docker_data.vhdx) 안에 ext4 가 그대로 있는지 **읽기만** 해서 본다 (2026-10-26 디스크 가득 찬 뒤)
  Docker 가 다시 켜며 이 디스크를 포맷(mkfs)하려 했다 — 켜기 전에 파일시스템 표시(ext4 슈퍼블록 0xEF53)가 살아 있는지 확인한다.
  py vhdx_check.py [경로]   (쓰지 않는다 · 'rb' 로만 연다)"""
import os, struct, sys, uuid
p = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ["LOCALAPPDATA"], "Docker", "wsl", "disk", "docker_data.vhdx")
print("파일", p, f"{os.path.getsize(p)/2**30:.1f}GB")
BAT = uuid.UUID("2DC27766-F623-4200-9D64-115E9BFD4A08"); META = uuid.UUID("8B7CA206-4790-4B9A-B8FE-575F050F886E")
BS = uuid.UUID("CAA16737-FA36-4D43-B3B6-33F0AA44E76B"); VS = uuid.UUID("2FA54224-CD1B-4876-B211-5DBED83BF4B8"); LSS = uuid.UUID("8141BF1D-A96F-4709-BA47-F233A8FAAB5F")
with open(p, "rb") as f:
    print("서명", f.read(8))
    f.seek(0x30000); rt = f.read(64 * 1024)
    assert rt[:4] == b"regi", rt[:4]
    n = struct.unpack_from("<I", rt, 8)[0]; reg = {}
    for i in range(n):
        g, off, ln, req = struct.unpack_from("<16sQII", rt, 16 + 32 * i); reg[uuid.UUID(bytes_le=g)] = (off, ln)
    mo, ml = reg[META]; f.seek(mo); md = f.read(ml)
    assert md[:8] == b"metadata"
    cnt = struct.unpack_from("<H", md, 10)[0]; vals = {}
    for i in range(cnt):
        g, off, ln, fl = struct.unpack_from("<16sIII", md, 32 + 32 * i); vals[uuid.UUID(bytes_le=g)] = md[off:off + ln]
    bsz = struct.unpack("<I", vals[BS][:4])[0]; vsz = struct.unpack("<Q", vals[VS][:8])[0]; lss = struct.unpack("<I", vals[LSS][:4])[0]
    print(f"블록 {bsz/2**20:.0f}MB · 가상 크기 {vsz/2**30:.0f}GB · 섹터 {lss}")
    bo, bl = reg[BAT]; f.seek(bo); e0 = struct.unpack("<Q", f.read(8))[0]
    st, offmb = e0 & 7, e0 >> 20
    print("첫 블록 상태", st, "파일 위치 MB", offmb)
    if st in (6, 7) and offmb:
        f.seek(offmb * 2**20 + 1024); sb = f.read(1024)
        magic = struct.unpack_from("<H", sb, 56)[0]
        blocks = struct.unpack_from("<I", sb, 4)[0]; free = struct.unpack_from("<I", sb, 12)[0]; lb = struct.unpack_from("<I", sb, 24)[0]
        bsz2 = 1024 << lb
        print(f"ext4 표시 0x{magic:04X} ({'살아 있음' if magic == 0xEF53 else '없음!'}) · 전체 {blocks*bsz2/2**30:.0f}GB · 빈 블록 {free*bsz2/2**30:.0f}GB(대략)")
        print("볼륨 이름", sb[120:136].rstrip(b'\0'), "UUID", uuid.UUID(bytes=sb[104:120]))
    else:
        print("첫 블록이 비어 있음(파일 안에 아직 안 만들어짐) — ext4 표시를 읽을 수 없음")
