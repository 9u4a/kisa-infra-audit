# N-06 (상) VTY 접근(ACL) 설정 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = VTY 접근을 제한하는 ACL 설정 / 취약 = 미설정
import re

from parsers import cisco_ios as cio


def check(ctx):
    vty_blocks = ctx.line_block_text("vty")
    if not vty_blocks:
        return {"status": "ERROR", "detail": "line vty 설정을 찾지 못함", "evidence": ""}
    # 번호 ACL 뿐 아니라 이름 ACL(access-class MGMT in)도 인정한다 - 예전 \d+ 패턴은 이름 ACL 을 거짓 VULN(진단 검수 D-R11).
    missing = [b for b in vty_blocks if not re.search(r"^\s*access-class \S+ in\b", b, re.M)]
    evidence = cio.mask_secrets("\n---\n".join(vty_blocks))  # password 값 미저장(진단 검수 D-R4)
    if missing:
        return {"status": "VULN", "detail": "VTY 라인에 access-class(ACL) 설정이 없는 라인이 존재함", "evidence": evidence}
    return {"status": "GOOD", "detail": "모든 VTY 라인에 access-class(ACL) 설정이 적용되어 있음", "evidence": evidence}
