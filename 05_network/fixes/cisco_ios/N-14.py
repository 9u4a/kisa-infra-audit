# N-14 (중) 정책에 따른 로깅 설정 [Cisco IOS] - 조치 명령어 생성
# checks/cisco_ios/N-14.py: VULN = logging 관련 설정이 전혀 없음. 기본적인 로깅 체계(버퍼+
# 콘솔 경고 이상)만 우선 활성화하고, 실제 기관 로그 기록 정책에 맞는 세부 조정은 N-11(원격 로그
# 서버)·N-13(버퍼 크기)과 함께 수동으로 검토하도록 안내한다.
def generate(ctx):
    return [
        "logging on",
        "logging buffered 16384",
        "logging console warnings",
        "! 기관의 로그 기록 정책(보관 기간, 원격 서버 전송 등)에 맞게 N-11/N-13과 함께 추가 조정할 것",
    ]
