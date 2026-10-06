# N-27 (중) 웹 서비스 차단 [Cisco IOS] - 조치 명령어 생성
# checks/cisco_ios/N-27.py: VULN = http/https 서비스가 활성화되어 있고 접근 제한이 없음.
# 업무상 웹 관리가 불필요하면 비활성화가 가장 안전하므로 기본 조치로 제시하고, 웹 관리가 필요한
# 경우를 위한 access-class 대안도 함께 안내한다.
def generate(ctx):
    cmds = []
    if ctx.has(r"^ip http server\s*$"):
        cmds.append("no ip http server")
    if ctx.has(r"^ip http secure-server\s*$"):
        cmds.append("no ip http secure-server")
    if cmds:
        cmds.append("! 웹 기반 관리가 반드시 필요하다면 비활성화 대신 아래처럼 접근 IP를 제한하는 것도 가능함:")
        cmds.append("! access-list 40 permit <관리자-PC-IP>")
        cmds.append("! ip http access-class 40")
    return cmds
