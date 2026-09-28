# N-02 (상) 비밀번호 복잡성 설정 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = 기관 정책에 맞는 비밀번호 복잡성 정책 설정(또는 기능이 없으면
#                        정책에 맞는 비밀번호 사용) / 취약 = 정책에 맞지 않는 비밀번호 사용
# 자동화 범위: "security passwords min-length" 설정 여부(메커니즘 존재)까지는 자동 판정하되,
# 실제 비밀번호 값이 기관 정책에 맞는지는 평문을 알 수 없어 항상 MANUAL 로 남긴다.
def check(ctx):
    m = ctx.search(r"^security passwords min-length (\d+)")
    if m:
        return {
            "status": "MANUAL",
            "detail": f"비밀번호 최소 길이 정책이 설정됨(min-length={m.group(1)}) - 기관 비밀번호 작성규칙에 맞는 값인지 수동 확인 필요",
            "evidence": m.group(0),
        }
    return {
        "status": "VULN",
        "detail": "security passwords min-length 설정이 없어 비밀번호 복잡성을 강제하는 메커니즘이 없음",
        "evidence": "",
    }
