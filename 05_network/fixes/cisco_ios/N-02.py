# N-02 (상) 비밀번호 복잡성 설정 [Cisco IOS] - 조치 명령어 생성
# checks/cisco_ios/N-02.py: VULN = security passwords min-length 설정이 전혀 없음.
# 가이드 원문은 "기관의 비밀번호 작성규칙"을 요구하므로 8자리를 안전한 기본값으로 제시하되,
# 실제 조직 정책에 맞게 조정하라는 안내를 함께 남긴다.
def generate(ctx):
    return [
        "security passwords min-length 8",
        "! 기관의 비밀번호 작성규칙에 맞는 값으로 조정할 것(위 8은 가이드 권고 하한값)",
    ]
