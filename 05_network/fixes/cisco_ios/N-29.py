# N-29 (중) Bootp 서비스 차단 [Cisco IOS] - 조치 명령어 생성
# 영향: BOOTP 서버 중지 — 이 장비에서 BOOTP 로 부팅·주소를 받던 장비 영향
def generate(ctx):
    return ["no ip bootp server"]
