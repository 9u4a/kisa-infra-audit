# N-07 (상) Session Timeout 설정 [Cisco IOS] - 조치 명령어 생성
# checks/cisco_ios/N-07.py: VULN = con/vty/aux 라인 중 exec-timeout 미설정 또는 10분 초과가
# 있음. 가이드 권고(10분 이하)를 충족하는 기본값(10분)을 모든 line 종류에 일괄 적용한다.
import re

from parsers import cisco_ios as cio


def generate(ctx):
    cmds = []
    for kind in ("con", "vty", "aux"):
        for b in ctx.line_block_text(kind):
            m = re.search(r"^\s*exec-timeout (\d+) (\d+)", b, re.M)
            if m and int(m.group(1)) <= 10:
                continue
            cmds.append(f"line {cio.iface_name(b)}")
            cmds.append("exec-timeout 10 0")
            cmds.append("exit")
    return cmds
