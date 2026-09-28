# N-34 (중) ICMP unreachable, redirect 차단 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = ICMP unreachable, redirect 모두 차단 / 취약 = 미차단
# 둘 다 인터페이스 기본값이 활성화이므로, IP가 설정된 인터페이스에 명시적 차단이 없으면
# 취약으로 판단한다.
import re


def check(ctx):
    ip_ifaces = ctx.ip_interface_blocks()
    if not ip_ifaces:
        return {"status": "NA", "detail": "IP가 설정된 인터페이스를 찾지 못함", "evidence": ""}
    missing = []
    for b in ip_ifaces:
        name = b.splitlines()[0]
        has_unreach = re.search(r"^\s*no ip unreachables\s*$", b, re.M)
        has_redirect = re.search(r"^\s*no ip redirects\s*$", b, re.M)
        if not (has_unreach and has_redirect):
            missing.append(f"{name}(unreachables={bool(has_unreach)}, redirects={bool(has_redirect)})")
    if not missing:
        return {"status": "GOOD", "detail": "모든 IP 인터페이스에 no ip unreachables/redirects 가 설정되어 있음", "evidence": ""}
    return {"status": "VULN", "detail": f"ICMP unreachable/redirect 차단이 누락된 인터페이스 {len(missing)}개 존재", "evidence": ", ".join(missing)}
