# N-04 (상) 계정 잠금 임계값 설정 [Cisco IOS] - 조치 명령어 생성
# checks/cisco_ios/N-04.py: VULN = login block-for 설정이 없거나 허용 실패 횟수가 5회 초과.
# 가이드 권고(5회 이하)를 충족하는 기본값을 제시한다. login block-for 는 실패가 누적되면 관리자를 포함한
# 모든 로그인을 일정 시간 막으므로(공격자가 일부러 실패를 일으켜 관리 접속을 막을 수도 있음) 관리망 예외
# 지정(login quiet-mode access-class)을 함께 안내한다.
def generate(ctx):
    return [
        "! 주의: 실패가 누적되면 관리자 포함 전체 로그인이 120초 차단됨 - 관리망은 아래처럼 예외로 지정 권장",
        "! login quiet-mode access-class <관리망-ACL>",
        "login block-for 120 attempts 5 within 60",
    ]
