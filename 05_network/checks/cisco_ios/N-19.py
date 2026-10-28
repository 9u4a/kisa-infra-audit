# N-19 (상) SNMP ACL 설정 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = SNMP 비활성화, 또는 SNMP 접근 제한 ACL 설정 / 취약 = ACL 미설정
from parsers import cisco_ios as cio


def check(ctx):
    # 예전 정규식(`<string> [RO|RW] [acl]$`)은 `view <이름>`·`ipv6 <acl>` 토큰이 있는 줄을 아예 놓쳐, 그런 줄만
    # 있으면 NA/GOOD 이 났다(진단 검수 D-R10). parse_snmp_community 로 토큰을 해석한다.
    community_lines = cio.snmp_community_lines(ctx)
    if not community_lines:
        return {"status": "NA", "detail": "SNMP community 설정이 없음(SNMP 미사용)", "evidence": ""}
    # Community String(비밀번호에 준함)은 증적에 원문으로 남기지 않고 <community> 로 마스킹한다.
    no_acl = []
    evidence_lines = []
    for line in community_lines:
        info = cio.parse_snmp_community(line)
        if info is None:
            continue
        masked = " ".join(["snmp-server", "community", "<community>"] + info["rest"])
        evidence_lines.append(masked)
        # IPv4 ACL 이 없으면(ipv6 ACL 만 있어도) IPv4 접근은 제한되지 않는다.
        if not info["acl"]:
            no_acl.append(masked)
    evidence = "\n".join(evidence_lines)
    if no_acl:
        return {"status": "VULN", "detail": f"ACL이 지정되지 않은 SNMP community 설정이 있음: {len(no_acl)}건", "evidence": evidence}
    return {"status": "GOOD", "detail": "모든 SNMP community 설정에 접근 제한 ACL이 지정되어 있음", "evidence": evidence}
