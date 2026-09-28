# N-35 (중) identd 서비스 차단 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = identd 서비스 차단 / 취약 = 미차단
# 참고(가이드 원문 명시): "IOS 12.2 이상 Default로 차단되어 있음" + "별도로 설정하지 않으면
# 비활성화 상태이며, 구성에서 no ip identd 명령어가 표시되지 않음" - 이는 가이드 원문이 직접
# 명시한 기본값이므로(추측이 아님), 명시적 활성화(ip identd)만 없으면 양호로 판단한다.
def check(ctx):
    if ctx.has(r"^ip identd\s*$"):
        return {"status": "VULN", "detail": "ip identd 가 명시적으로 활성화되어 있음", "evidence": "ip identd"}
    return {"status": "GOOD", "detail": "identd 활성화 설정이 없음(가이드 원문 기준 기본 차단 상태)", "evidence": ""}
