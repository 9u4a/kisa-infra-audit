# N-23 (상) DDoS 공격 방어 설정 또는 DDoS 장비 사용 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = 경계 라우터에서 DDoS 방어 설정 또는 DDoS 대응 장비 사용
#                        취약 = 둘 다 하지 않음
# 설정 텍스트만으로 별도 DDoS 대응 장비 사용 여부를 알 수 없고, 방어 설정도 공격 유형별로
# 다양해 일반화하기 어려움 - 항상 MANUAL. rate-limit/TCP intercept 설정 존재 여부만 증적 제공.
def check(ctx):
    hints = []
    if ctx.has(r"^ip tcp intercept"):
        hints.append("ip tcp intercept 설정 발견")
    if ctx.has(r"rate-limit"):
        hints.append("rate-limit 설정 발견")
    evidence = "\n".join(hints)
    return {"status": "MANUAL", "detail": "DDoS 방어 설정 또는 별도 DDoS 대응 장비 사용 여부는 설정 텍스트만으로 판정 불가 - 수동 확인 필요" + (f" (참고: {', '.join(hints)})" if hints else ""), "evidence": evidence}
