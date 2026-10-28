# N-20 (상) SNMP Community 권한 설정 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = SNMP 커뮤니티 권한이 RO(읽기 전용) / 취약 = RW(읽기 쓰기)
# 주의: Cisco IOS는 RO/RW를 생략하면 기본값이 RW이므로, 명시적 RO가 없으면 취약으로 판단한다.
from parsers import cisco_ios as cio


def check(ctx):
    # view/ipv6 토큰이 있는 줄도 해석한다(진단 검수 D-R10 - 예전 정규식은 그런 줄을 놓쳤다).
    community_lines = cio.snmp_community_lines(ctx)
    if not community_lines:
        return {"status": "NA", "detail": "SNMP community 설정이 없음(SNMP 미사용)", "evidence": ""}
    # Community String은 증적에 원문으로 남기지 않고 마스킹한다.
    evidence_lines = []
    rw_count = 0
    for line in community_lines:
        info = cio.parse_snmp_community(line)
        if info is None:
            continue
        if info["mode"] != "RO":  # RO/RW 생략 시 기본값은 RW
            rw_count += 1
        evidence_lines.append(" ".join(["snmp-server", "community", "<community>"] + info["rest"]))
    evidence = "\n".join(evidence_lines)
    if rw_count:
        return {"status": "VULN", "detail": f"읽기-쓰기(RW) 권한의 SNMP community 설정이 {rw_count}건 존재함", "evidence": evidence}
    return {"status": "GOOD", "detail": "모든 SNMP community가 읽기 전용(RO)으로 설정됨", "evidence": evidence}
