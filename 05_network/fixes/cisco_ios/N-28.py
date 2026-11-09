# N-28 (중) TCP/UDP small 서비스 차단 [Cisco IOS] - 조치 명령어 생성
# 영향: 실행 중인 TCP/UDP small 서비스(echo·discard 등) 중지 — 이를 쓰는 점검 도구 동작 중단
def generate(ctx):
    cmds = []
    if ctx.has(r"^service tcp-small-servers\b"):
        cmds.append("no service tcp-small-servers")
    if ctx.has(r"^service udp-small-servers\b"):
        cmds.append("no service udp-small-servers")
    return cmds
