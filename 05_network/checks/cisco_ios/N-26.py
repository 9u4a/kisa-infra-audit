# N-26 (중) Finger 서비스 차단 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = Finger 서비스 차단 / 취약 = 차단하지 않음
# 참고(가이드 원문): "12.1(5) 및 12.1(5)T 이상은 기본적으로 비활성화" - 설정 텍스트에 명시적
# 차단 라인이 없어도 최신 버전이면 안전할 수 있으나, IOS 버전을 신뢰성 있게 알 수 없는 한 임의로
# 안전하다고 가정하지 않는다(과거 W-48 레지스트리 기본값 오판 사례와 동일 원칙).
def check(ctx):
    if ctx.has(r"^service finger\s*$"):
        return {"status": "VULN", "detail": "service finger 가 명시적으로 활성화되어 있음", "evidence": "service finger"}
    if ctx.has(r"^no (service finger|ip finger)\s*$"):
        return {"status": "GOOD", "detail": "Finger 서비스가 명시적으로 차단되어 있음", "evidence": ""}
    return {"status": "MANUAL", "detail": "Finger 차단 설정을 찾지 못함 - IOS 12.1(5) 이상은 기본 비활성화이나 실제 버전을 확인해 판단 필요", "evidence": ""}
