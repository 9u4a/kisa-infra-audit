# N-33 (중) Proxy ARP 차단 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = Proxy ARP 차단 / 취약 = 미차단
# Proxy ARP는 인터페이스 기본값이 활성화이므로, IP가 설정된 인터페이스에 명시적 차단이 없으면
# 취약으로 판단한다.
import re


def check(ctx):
    ip_ifaces = ctx.ip_interface_blocks()
    if not ip_ifaces:
        return {"status": "NA", "detail": "IP가 설정된 인터페이스를 찾지 못함", "evidence": ""}
    missing = [b.splitlines()[0] for b in ip_ifaces if not re.search(r"^\s*no ip proxy-arp\s*$", b, re.M)]
    if not missing:
        return {"status": "GOOD", "detail": "모든 IP 인터페이스에 no ip proxy-arp 가 설정되어 있음", "evidence": ""}
    return {"status": "VULN", "detail": f"no ip proxy-arp 설정이 없는(기본값=활성화) 인터페이스 {len(missing)}개 존재", "evidence": ", ".join(missing)}
