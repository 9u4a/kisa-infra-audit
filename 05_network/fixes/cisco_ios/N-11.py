# N-11 (중) 원격로그 서버 사용 [Cisco IOS] - 조치 명령어 생성
# checks/cisco_ios/N-11.py: VULN = logging <IP> (원격 syslog 서버) 설정이 없음. 실제 로그
# 서버 IP는 설정 텍스트만으로 알 수 없으므로 자리표시자를 반드시 교체해야 한다.
def generate(ctx):
    return [
        "! 주의: 아래 IP를 실제 로그 서버 주소로 교체할 것",
        "logging host <로그-서버-IP>",
        "logging trap informational",
    ]
