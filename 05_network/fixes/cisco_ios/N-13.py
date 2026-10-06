# N-13 (중) 로깅 버퍼 크기 설정 [Cisco IOS] - 조치 명령어 생성
# checks/cisco_ios/N-13.py: VULN = logging buffered 크기가 가이드 권고(16~32KB)보다 작거나
# 미설정. 권고 범위 내 값(16384)을 기본값으로 제시한다.
def generate(ctx):
    return ["logging buffered 16384"]
