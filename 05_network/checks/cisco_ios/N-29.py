# N-29 (중) Bootp 서비스 차단 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = BOOTP 서비스 제한 / 취약 = 미제한
# BOOTP 서버 기능은 기본적으로 켜져 있는 서비스이므로(가이드 원문 "자동 재부팅 취약점 존재하므로
# 차단 권고"), 명시적 차단이 없으면 취약으로 판단한다.
def check(ctx):
    if ctx.has(r"^no ip bootp server\s*$") or ctx.has(r"^ip dhcp bootp ignore\s*$"):
        return {"status": "GOOD", "detail": "BOOTP 서비스가 차단되어 있음(no ip bootp server 또는 ip dhcp bootp ignore)", "evidence": ""}
    return {"status": "VULN", "detail": "BOOTP 서비스 차단 설정이 없음", "evidence": ""}
