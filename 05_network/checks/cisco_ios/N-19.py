# N-19 (상) SNMP ACL 설정 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = SNMP 비활성화, 또는 SNMP 접근 제한 ACL 설정 / 취약 = ACL 미설정
import re


def check(ctx):
    # 주의: \s 는 개행도 포함하므로 옵션 그룹에 쓰면 다음 줄(예: "!")까지 캡처해버리는 버그가 있었다
    # (실기 테스트로 발견). 줄 내부 공백만 매치하도록 [ \t] 를 사용해 줄 경계를 넘지 않게 한다.
    community_lines = ctx.find(r"^(snmp-server community \S+(?:[ \t]+(?:RO|RW))?(?:[ \t]+\S+)?)[ \t]*$")
    if not community_lines:
        return {"status": "NA", "detail": "SNMP community 설정이 없음(SNMP 미사용)", "evidence": ""}
    # Community String(비밀번호에 준함)은 증적에 원문으로 남기지 않고 <community> 로 마스킹한다.
    no_acl = []
    evidence_lines = []
    for line in community_lines:
        tokens = line.split()
        # tokens: ['snmp-server','community','<string>', optional 'RO'/'RW', optional acl]
        rest = tokens[3:]
        has_acl = any(t not in ("RO", "RW") for t in rest)
        masked = " ".join(["snmp-server", "community", "<community>"] + rest)
        evidence_lines.append(masked)
        if not has_acl:
            no_acl.append(masked)
    evidence = "\n".join(evidence_lines)
    if no_acl:
        return {"status": "VULN", "detail": f"ACL이 지정되지 않은 SNMP community 설정이 있음: {len(no_acl)}건", "evidence": evidence}
    return {"status": "GOOD", "detail": "모든 SNMP community 설정에 접근 제한 ACL이 지정되어 있음", "evidence": evidence}
