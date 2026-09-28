# N-37 (중) pad 차단 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = PAD 서비스 차단 / 취약 = 미차단(기본값이 활성화)
def check(ctx):
    if ctx.has(r"^no service pad\s*$"):
        return {"status": "GOOD", "detail": "no service pad 설정으로 PAD 서비스가 차단되어 있음", "evidence": ""}
    return {"status": "VULN", "detail": "no service pad 설정이 없어 PAD 서비스가 차단되어 있지 않음", "evidence": ""}
