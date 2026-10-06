# N-30 (중) CDP 서비스 차단 [Cisco IOS] - 조치 명령어 생성
# 주의: no cdp run 은 전역 설정이라 네트워크 토폴로지 파악용으로 CDP를 쓰는 인접 장비 관리 도구가
# 있다면 영향을 줄 수 있다 - 적용 전 CDP 의존 여부를 확인할 것.
def generate(ctx):
    return ["no cdp run"]
