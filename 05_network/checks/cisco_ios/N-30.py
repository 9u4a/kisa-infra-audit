# N-30 (중) CDP 서비스 차단 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = CDP 서비스 차단 / 취약 = 미차단
# CDP는 기본적으로 활성화되어 있는 서비스이므로 명시적 차단이 없으면 취약으로 판단한다.
def check(ctx):
    if ctx.has(r"^no cdp run\s*$"):
        return {"status": "GOOD", "detail": "no cdp run 설정으로 CDP 서비스가 전역 차단되어 있음", "evidence": ""}
    return {"status": "VULN", "detail": "no cdp run 설정이 없어 CDP 서비스가 차단되어 있지 않음", "evidence": ""}
