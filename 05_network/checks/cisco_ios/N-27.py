# N-27 (중) 웹 서비스 차단 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = 불필요한 웹 서비스 차단 또는 허용 IP만 접속 가능 / 취약 = 미차단
# `ip http access-class` 가 있어도 참조한 ACL 이 정의되지 않았거나 any 를 허용하면 "허용 IP만 접속 가능"이 아니다
# (외부 검수 A13 - 예전에는 access-class 존재만 보고 GOOD). `ip http access-class ipv4 <이름>` 형식도 본다.
from parsers import cisco_ios as cio


def check(ctx):
    http_on = ctx.has(r"^ip http server\s*$")
    https_on = ctx.has(r"^ip http secure-server\s*$")
    if not http_on and not https_on:
        return {"status": "GOOD", "detail": "ip http server/secure-server 가 모두 비활성화되어 있음", "evidence": ""}
    found = ctx.find(r"^ip http access-class (?:ipv4 )?(\S+)")
    acl = found[-1] if found else None
    evidence = f"http={http_on}, https={https_on}, access-class={acl or '없음'}"
    if not acl:
        return {"status": "VULN", "detail": "웹 서비스(http/https)가 활성화되어 있고 접근 제한(access-class)이 없음", "evidence": evidence}
    evidence += "\n" + cio.acl_evidence(ctx, acl)
    problem = cio.acl_problem(ctx, acl)
    if problem:
        return {"status": "VULN", "detail": f"웹 서비스(http/https)가 활성화되어 있고 access-class 가 접근을 제한하지 못함 - {problem}", "evidence": evidence}
    return {"status": "GOOD", "detail": "웹 서비스가 활성화되어 있으나 접근 IP가 정의된 ACL(access-class)로 제한되어 있음", "evidence": evidence}
