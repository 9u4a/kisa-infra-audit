# N-34 (중) ICMP unreachable, redirect 차단 [Cisco IOS] - 조치 명령어 생성
# checks/cisco_ios/N-34.py: VULN = no ip unreachables/no ip redirects 중 하나라도 누락된
# IP 인터페이스 존재(둘 다 기본값이 활성화).
import re

from parsers import cisco_ios as cio


def generate(ctx):
    cmds = []
    for b in ctx.ip_interface_blocks():
        has_unreach = re.search(r"^\s*no ip unreachables\s*$", b, re.M)
        has_redirect = re.search(r"^\s*no ip redirects\s*$", b, re.M)
        if has_unreach and has_redirect:
            continue
        cmds.append(f"interface {cio.iface_name(b)}")
        if not has_unreach:
            cmds.append("no ip unreachables")
        if not has_redirect:
            cmds.append("no ip redirects")
        cmds.append("exit")
    return cmds
