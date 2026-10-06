# N-09 (중) 불필요한 보조 입출력 포트 사용 금지 [Cisco IOS] - 조치 명령어 생성
# checks/cisco_ios/N-09.py: VULN = AUX 포트가 설정되어 있으나 차단되어 있지 않음(AUX 라인
# 자체가 없으면 MANUAL이라 여기서는 다루지 않음).
from parsers import cisco_ios as cio


def generate(ctx):
    cmds = []
    for b in ctx.line_block_text("aux"):
        cmds.append(f"line {cio.iface_name(b)}")
        cmds.append("transport input none")
        cmds.append("no exec")
        cmds.append("exit")
    return cmds
