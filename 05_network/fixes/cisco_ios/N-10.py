# N-10 (중) 로그인 시 경고 메시지 설정 [Cisco IOS] - 조치 명령어 생성
# checks/cisco_ios/N-10.py: VULN = banner motd/login/exec 설정이 전혀 없음. 가이드 원문이
# 금지하는 "시스템 정보 노출"이 없는 일반적인 경고 문구를 기본값으로 제시한다.
def generate(ctx):
    return [
        "banner motd ^C",
        "WARNING: Unauthorized access to this device is prohibited.",
        "All activity may be monitored and recorded.",
        "^C",
    ]
