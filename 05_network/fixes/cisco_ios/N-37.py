# N-37 (중) pad 차단 [Cisco IOS] - 조치 명령어 생성
# 영향: PAD 서비스 중지 — X.25 PAD 로 접속하던 경로 끊김
def generate(ctx):
    return ["no service pad"]
