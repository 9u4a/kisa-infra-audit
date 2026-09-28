# N-25 (중) TCP Keepalive 서비스 설정 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = TCP Keepalive 서비스 설정 / 취약 = 미설정
def check(ctx):
    has_in = ctx.has(r"^service tcp-keepalives-in\s*$")
    has_out = ctx.has(r"^service tcp-keepalives-out\s*$")
    evidence = f"tcp-keepalives-in={has_in}, tcp-keepalives-out={has_out}"
    if has_in and has_out:
        return {"status": "GOOD", "detail": "TCP Keepalive(in/out) 서비스가 모두 설정되어 있음", "evidence": evidence}
    return {"status": "VULN", "detail": "TCP Keepalive 서비스가 설정되어 있지 않음", "evidence": evidence}
