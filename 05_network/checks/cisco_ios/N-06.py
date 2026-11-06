# N-06 (상) VTY 접근(ACL) 설정 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = VTY 접근을 제한하는 ACL 설정 / 취약 = 미설정
# access-class 줄이 있어도 참조한 ACL 이 정의되지 않았거나 any 를 허용하면 접근이 제한되지 않으므로 취약이다
# (외부 검수 A13 - 예전에는 access-class 존재만 보고 GOOD).
from parsers import cisco_ios as cio


def check(ctx):
    vty_blocks = ctx.line_block_text("vty")
    if not vty_blocks:
        return {"status": "ERROR", "detail": "line vty 설정을 찾지 못함", "evidence": ""}
    problems = cio.vty_acl_problems(ctx)
    acls = sorted({a for a in (cio.vty_access_class(b) for b in vty_blocks) if a})
    evidence = cio.mask_secrets("\n---\n".join(vty_blocks))  # password 값 미저장(진단 검수 D-R4)
    if acls:
        evidence += "\n---\n" + "\n".join(cio.acl_evidence(ctx, a) for a in acls)
    if problems:
        reasons = "; ".join(f"{cio.iface_name(b)}: {p}" for b, p in problems)
        return {"status": "VULN", "detail": f"VTY 접근을 제한하지 못하는 라인이 있음 - {reasons}", "evidence": evidence}
    return {"status": "GOOD", "detail": "모든 VTY 라인에 정의된 ACL 이 access-class 로 적용되어 있고 any 허용이 없음", "evidence": evidence}
