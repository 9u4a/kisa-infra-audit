# N-21 (상) TFTP 서비스 차단 [Cisco IOS] - 조치 명령어 생성
# checks/cisco_ios/N-21.py: VULN = tftp-server 가 ACL 제한 없이 구동 중. 업무상 TFTP가
# 불필요하면 서비스 자체를 끄는 것이 가장 안전하므로 기본 조치는 비활성화로 제시하고, 업무상
# 필요한 경우를 위해 ACL로 제한하는 대안도 주석으로 함께 안내한다.
def generate(ctx):
    m = ctx.search(r"^tftp-server\b.*$")
    if not m:
        return []
    return [
        "no tftp-server",
        f"! 원본 설정: {m.group(0)}",
        "! 업무상 TFTP가 반드시 필요하다면 완전 차단 대신 ACL로 제한하는 것도 가능함, 예:",
        "! access-list 30 permit <허용-시스템-IP>",
        f"! {m.group(0)} 30   (원본 명령 끝에 ACL 번호 추가하여 재적용)",
    ]
