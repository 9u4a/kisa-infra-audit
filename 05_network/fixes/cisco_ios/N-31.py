# N-31 (중) Directed-broadcast 차단 [Cisco IOS] - 조치 명령어 생성 (1.4.0)
# checks/cisco_ios/N-31.py: VULN = `ip directed-broadcast` 가 명시적으로 허용된 IP 인터페이스 존재.
# 가이드 조치(Step 2)대로 명시적 차단이 없는 모든 IP 인터페이스에 no ip directed-broadcast 를 넣는다
# (허용 줄은 이 명령으로 대체되고, 기본값에 기대던 인터페이스도 명시적으로 차단해 버전 의존을 없앤다).
import re

from parsers import cisco_ios as cio


def generate(ctx):
    cmds = []
    for b in ctx.ip_interface_blocks():
        if re.search(r"^\s*no ip directed-broadcast\s*$", b, re.M):
            continue
        cmds.append(f"interface {cio.iface_name(b)}")
        cmds.append("no ip directed-broadcast")
        cmds.append("exit")
    return cmds
