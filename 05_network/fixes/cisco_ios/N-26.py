# N-26 (중) Finger 서비스 차단 [Cisco IOS] - 조치 명령어 생성
# 영향: 실행 중인 finger 서비스 중지
def generate(ctx):
    return ["no service finger"] if ctx.has(r"^service finger\s*$") else []
