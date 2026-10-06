# N-33 (중) Proxy ARP 차단 [Cisco IOS] - 조치 명령어 생성
# checks/cisco_ios/N-33.py: VULN = no ip proxy-arp 설정이 없는(기본값=활성화) IP 인터페이스 존재.
import re

from parsers import cisco_ios as cio


def generate(ctx):
    cmds = []
    for b in ctx.ip_interface_blocks():
        if re.search(r"^\s*no ip proxy-arp\s*$", b, re.M):
            continue
        cmds.append(f"interface {cio.iface_name(b)}")
        cmds.append("no ip proxy-arp")
        cmds.append("exit")
    return cmds
