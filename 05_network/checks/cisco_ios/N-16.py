# N-16 (하) Timestamp 로그 설정 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = timestamp 로그 설정 있음 / 취약 = 없음
def check(ctx):
    m = ctx.search(r"^service timestamps log \S+.*$")
    if m:
        return {"status": "GOOD", "detail": "service timestamps log 설정이 되어 있음", "evidence": m.group(0)}
    return {"status": "VULN", "detail": "service timestamps log 설정이 없음", "evidence": ""}
