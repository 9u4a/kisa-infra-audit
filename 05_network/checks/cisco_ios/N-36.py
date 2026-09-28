# N-36 (중) Domain Lookup 차단 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = Domain Lookup 차단 / 취약 = 미차단(기본값이 활성화)
def check(ctx):
    if ctx.has(r"^no ip domain[ -]lookup\s*$"):
        return {"status": "GOOD", "detail": "no ip domain-lookup 설정으로 Domain Lookup이 차단되어 있음", "evidence": ""}
    return {"status": "VULN", "detail": "no ip domain-lookup 설정이 없어 Domain Lookup이 차단되어 있지 않음", "evidence": ""}
