# N-08 (중) VTY 접속 시 안전한 프로토콜 사용 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = SSH만 허용 / 취약 = telnet 허용
import re


def check(ctx):
    vty_blocks = ctx.line_block_text("vty")
    if not vty_blocks:
        return {"status": "ERROR", "detail": "line vty 설정을 찾지 못함", "evidence": ""}
    evidence = "\n---\n".join(vty_blocks)
    telnet_allowed = any(
        re.search(r"^\s*transport input (all|telnet)", b, re.M) or not re.search(r"^\s*transport input", b, re.M)
        for b in vty_blocks
    )
    if telnet_allowed:
        return {"status": "VULN", "detail": "VTY 라인이 telnet을 허용하거나 transport input이 기본값(all)으로 남아있음", "evidence": evidence}
    return {"status": "GOOD", "detail": "모든 VTY 라인이 SSH만 허용하도록 설정되어 있음(transport input ssh)", "evidence": evidence}
