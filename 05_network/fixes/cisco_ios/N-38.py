# N-38 (중) mask-reply 차단 [Cisco IOS] - 조치 명령어 생성
# checks/cisco_ios/N-38.py: VULN = ip mask-reply 가 명시적으로 활성화된 IP 인터페이스 존재.
import re

from parsers import cisco_ios as cio


def generate(ctx):
    cmds = []
    for b in ctx.ip_interface_blocks():
        if not re.search(r"^\s*ip mask-reply\s*$", b, re.M):
            continue
        cmds.append(f"interface {cio.iface_name(b)}")
        cmds.append("no ip mask-reply")
        cmds.append("exit")
    return cmds
