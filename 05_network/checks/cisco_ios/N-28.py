# N-28 (중) TCP/UDP small 서비스 차단 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = TCP/UDP Small 서비스 제한 / 취약 = 미제한
# 참고(가이드 원문): "IOS 11.3 이상에서는 기본적으로 서비스가 제거된 상태" - 낮은 버전만 별도
# 설정이 필요하다고 명시하므로, 명시적 활성화(service ...-small-servers, 인자 없이 또는 max-servers
# 지정)가 없는 한 위협으로 단정하지 않되, 명시적 차단이 보이면 GOOD으로 명확히 표기한다.
def check(ctx):
    if ctx.has(r"^service (tcp|udp)-small-servers\b"):
        return {"status": "VULN", "detail": "service tcp/udp-small-servers 가 명시적으로 활성화되어 있음", "evidence": ""}
    if ctx.has(r"^no service (tcp|udp)-small-servers\s*$"):
        return {"status": "GOOD", "detail": "TCP/UDP small 서비스가 명시적으로 차단되어 있음", "evidence": ""}
    return {"status": "MANUAL", "detail": "TCP/UDP small 서비스 관련 설정을 찾지 못함 - IOS 11.3 이상은 기본 차단 상태이나 실제 버전을 확인해 판단 필요", "evidence": ""}
