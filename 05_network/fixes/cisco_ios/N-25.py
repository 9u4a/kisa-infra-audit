# N-25 (중) TCP Keepalive 서비스 설정 [Cisco IOS] - 조치 명령어 생성
def generate(ctx):
    cmds = []
    if not ctx.has(r"^service tcp-keepalives-in\s*$"):
        cmds.append("service tcp-keepalives-in")
    if not ctx.has(r"^service tcp-keepalives-out\s*$"):
        cmds.append("service tcp-keepalives-out")
    return cmds
