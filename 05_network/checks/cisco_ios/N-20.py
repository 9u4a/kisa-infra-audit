# N-20 (상) SNMP Community 권한 설정 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = SNMP 커뮤니티 권한이 RO(읽기 전용) / 취약 = RW(읽기 쓰기)
# 주의: Cisco IOS는 RO/RW를 생략하면 기본값이 RW이므로, 명시적 RO가 없으면 취약으로 판단한다.
def check(ctx):
    # 주의: \s 는 개행도 포함하므로 옵션 그룹에 쓰면 다음 줄(예: "!")까지 캡처해버리는 버그가 있었다
    # (N-19에서 실기 테스트로 발견). 줄 내부 공백만 매치하도록 [ \t] 를 사용해 줄 경계를 넘지 않게 한다.
    community_lines = ctx.find(r"^(snmp-server community \S+(?:[ \t]+(?:RO|RW))?(?:[ \t]+\S+)?)[ \t]*$")
    if not community_lines:
        return {"status": "NA", "detail": "SNMP community 설정이 없음(SNMP 미사용)", "evidence": ""}
    # Community String은 증적에 원문으로 남기지 않고 마스킹한다.
    evidence_lines = []
    rw_count = 0
    for line in community_lines:
        tokens = line.split()
        rest = tokens[3:]
        is_rw = "RW" in rest or "RO" not in rest  # RO/RW 생략 시 기본값은 RW
        if is_rw:
            rw_count += 1
        masked = " ".join(["snmp-server", "community", "<community>"] + rest)
        evidence_lines.append(masked)
    evidence = "\n".join(evidence_lines)
    if rw_count:
        return {"status": "VULN", "detail": f"읽기-쓰기(RW) 권한의 SNMP community 설정이 {rw_count}건 존재함", "evidence": evidence}
    return {"status": "GOOD", "detail": "모든 SNMP community가 읽기 전용(RO)으로 설정됨", "evidence": evidence}
