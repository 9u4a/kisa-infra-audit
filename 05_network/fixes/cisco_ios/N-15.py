# N-15 (중) NTP 및 시각 동기화 설정 [Cisco IOS] - 조치 명령어 생성
# checks/cisco_ios/N-15.py: VULN = ntp server 설정이 없음. 실제 NTP 서버 주소는 설정 텍스트
# 만으로 알 수 없으므로 자리표시자를 반드시 교체해야 한다.
def generate(ctx):
    return ["! 주의: 아래 IP를 실제 NTP 서버 주소로 교체할 것", "ntp server <NTP-서버-IP>"]
