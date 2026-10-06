# N-35 (중) identd 서비스 차단 [Cisco IOS] - 조치 명령어 생성
def generate(ctx):
    return ["no ip identd"] if ctx.has(r"^ip identd\s*$") else []
