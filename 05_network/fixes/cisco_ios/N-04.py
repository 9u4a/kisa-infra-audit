# N-04 (상) 계정 잠금 임계값 설정 [Cisco IOS] - 조치 명령어 생성
# checks/cisco_ios/N-04.py: VULN = login block-for 설정이 없거나 허용 실패 횟수가 5회 초과.
# 가이드 권고(5회 이하)를 충족하는 기본값을 제시한다.
def generate(ctx):
    return ["login block-for 120 attempts 5 within 60"]
