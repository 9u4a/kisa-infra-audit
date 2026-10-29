# N-07 (상) Session Timeout 설정 [Cisco IOS] - 조치 명령어 생성
# checks/cisco_ios/N-07.py: VULN = con/vty/aux 라인 중 exec-timeout 미설정·0 0(무제한)·10분 초과가
# 있음. 가이드 권고(10분 이하)를 충족하는 기본값(10분)을 해당 line 에 적용한다(판정은 check 와 같은 헬퍼 사용).
from parsers import cisco_ios as cio


def generate(ctx):
    cmds = []
    for kind in ("con", "vty", "aux"):
        for b in ctx.line_block_text(kind):
            sec = cio.exec_timeout_seconds(b)
            if sec is not None and 0 < sec <= 600:
                continue
            cmds.append(f"line {cio.iface_name(b)}")
            cmds.append("exec-timeout 10 0")
            cmds.append("exit")
    return cmds
