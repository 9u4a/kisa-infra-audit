# N-11 (중) 원격로그 서버 사용 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = 별도 로그 서버로 로그 관리 / 취약 = 로그 서버 없음
def check(ctx):
    m = ctx.search(r"^logging (?:host )?(\d{1,3}(?:\.\d{1,3}){3})")
    if m:
        return {"status": "GOOD", "detail": f"원격 syslog 서버가 설정되어 있음({m.group(1)})", "evidence": m.group(0)}
    return {"status": "VULN", "detail": "원격 syslog 서버(logging <IP>) 설정이 없음", "evidence": ""}
