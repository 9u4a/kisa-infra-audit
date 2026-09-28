# N-13 (중) 로깅 버퍼 크기 설정 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = 저장되는 로그보다 버퍼 용량이 큰 경우 / 취약 = 버퍼가 더 작은 경우
# 자동화 범위: 실제 로그 발생량은 알 수 없으므로, 가이드가 권고하는 16~32KB 이상 설정 여부를
# 대리 지표로 사용한다.
def check(ctx):
    m = ctx.search(r"^logging buffered (\d+)")
    if not m:
        return {"status": "VULN", "detail": "logging buffered 설정이 없음(버퍼 크기 미설정)", "evidence": ""}
    size = int(m.group(1))
    evidence = m.group(0)
    if size >= 16000:
        return {"status": "GOOD", "detail": f"로깅 버퍼 크기가 {size}byte로 설정됨(가이드 권고 16~32KB 이상)", "evidence": evidence}
    return {"status": "VULN", "detail": f"로깅 버퍼 크기가 {size}byte로 가이드 권고(16~32KB)보다 작게 설정됨", "evidence": evidence}
