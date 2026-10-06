# N-08 (중) VTY 접속 시 안전한 프로토콜 사용 [Cisco IOS] - 조치 명령어 생성
# checks/cisco_ios/N-08.py: VULN = VTY 라인이 telnet을 허용(또는 transport input 기본값).
# transport input ssh 를 적용하기 전에 SSH 서비스 자체(도메인명/RSA 키/ip ssh version 2)가
# 먼저 구성되어 있어야 한다 - 안 되어 있는 상태로 적용하면 VTY 접근이 전부 끊어질 수 있다.
from parsers import cisco_ios as cio


def generate(ctx):
    vty_blocks = ctx.line_block_text("vty")
    import re

    bad = [
        b
        for b in vty_blocks
        if re.search(r"^\s*transport input (all|telnet)", b, re.M) or not re.search(r"^\s*transport input", b, re.M)
    ]
    if not bad:
        return []
    cmds = []
    if not ctx.has(r"^ip domain[ -]name \S+"):
        cmds.append("! 주의: SSH 사용 전 아래 선행 설정이 필요함(미설정 시 VTY 접근이 끊길 수 있음)")
        cmds.append("ip domain-name <실제 도메인명으로 교체>")
        cmds.append("crypto key generate rsa modulus 2048")
        cmds.append("ip ssh version 2")
    for b in bad:
        cmds.append(f"line {cio.iface_name(b)}")
        cmds.append("transport input ssh")
        cmds.append("exit")
    return cmds
