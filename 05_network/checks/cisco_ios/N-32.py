# N-32 (중) Source Routing 차단 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = ip source-route 차단 / 취약 = 미차단(전역 설정, 기본값이 활성화)
def check(ctx):
    if ctx.has(r"^no ip source-route\s*$"):
        return {"status": "GOOD", "detail": "no ip source-route 설정으로 Source Routing이 전역 차단되어 있음", "evidence": ""}
    return {"status": "VULN", "detail": "no ip source-route 설정이 없어 Source Routing이 차단되어 있지 않음", "evidence": ""}
