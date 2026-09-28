# N-04 (상) 계정 잠금 임계값 설정 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = 로그인 실패 임계값이 5회 이하로 설정된 경우
#                        취약 = 설정되어 있지 않거나 5회 초과로 설정된 경우
def check(ctx):
    m = ctx.search(r"^login block-for (\d+) attempts (\d+) within (\d+)")
    if not m:
        return {"status": "VULN", "detail": "login block-for 설정이 없어 로그인 실패 임계값이 설정되어 있지 않음", "evidence": ""}
    block_for, attempts, within = (int(x) for x in m.groups())
    evidence = m.group(0)
    if attempts <= 5:
        return {"status": "GOOD", "detail": f"로그인 실패 임계값이 {attempts}회로 설정됨(5회 이하)", "evidence": evidence}
    return {"status": "VULN", "detail": f"로그인 실패 임계값이 {attempts}회로 설정됨(5회 초과)", "evidence": evidence}
