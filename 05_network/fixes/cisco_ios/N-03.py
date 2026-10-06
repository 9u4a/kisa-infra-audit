# N-03 (상) 암호화된 비밀번호 사용 [Cisco IOS] - 조치 명령어 생성
# checks/cisco_ios/N-03.py: VULN = enable password 만 평문으로 사용 중(enable secret/
# service password-encryption 없음). service password-encryption 은 모든 평문 비밀번호를
# 가변(Type 7) 암호화하는 전역 설정이라 즉시 적용 가능하지만, Type 7 은 해독 가능한 약한 암호화라
# enable secret(단방향 해시)로 전환하는 것이 더 안전함을 함께 안내한다.
def generate(ctx):
    return [
        "service password-encryption",
        "! service password-encryption(Type 7)은 해독 가능한 약한 암호화이므로, 가능하면",
        "! enable secret <비밀번호> 로 전환해 단방향 해시(Type 5/8/9)를 사용할 것",
    ]
