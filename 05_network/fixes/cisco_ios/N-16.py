# N-16 (하) Timestamp 로그 설정 [Cisco IOS] - 조치 명령어 생성
# checks/cisco_ios/N-16.py: VULN = service timestamps log 설정이 없음.
def generate(ctx):
    return ["service timestamps log datetime msec localtime show-timezone"]
