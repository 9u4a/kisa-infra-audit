# N-06 (상) VTY 접근(ACL) 설정 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = VTY 접근을 제한하는 ACL 설정 / 취약 = 미설정
import re


def check(ctx):
    vty_blocks = ctx.line_block_text("vty")
    if not vty_blocks:
        return {"status": "ERROR", "detail": "line vty 설정을 찾지 못함", "evidence": ""}
    missing = [b for b in vty_blocks if not re.search(r"^\s*access-class \d+ in", b, re.M)]
    evidence = "\n---\n".join(vty_blocks)
    if missing:
        return {"status": "VULN", "detail": "VTY 라인에 access-class(ACL) 설정이 없는 라인이 존재함", "evidence": evidence}
    return {"status": "GOOD", "detail": "모든 VTY 라인에 access-class(ACL) 설정이 적용되어 있음", "evidence": evidence}
