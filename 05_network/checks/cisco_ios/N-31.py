# N-31 (중) Directed-broadcast 차단 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = Directed Broadcast 차단 / 취약 = 미차단
# 참고: IOS 12.0 이후 기본값이 비활성화(차단)로 바뀌었으나, 버전을 신뢰성 있게 알 수 없으므로
# IP가 설정된 인터페이스에 명시적 차단이 없으면 MANUAL(버전에 따라 다를 수 있음)로 남긴다.
# 단, `ip directed-broadcast [ACL]` 이 명시된 인터페이스는 버전과 무관하게 허용 상태이므로 VULN(1.4.0, N-R4 -
# 예전에는 명시적 허용도 MANUAL 로 남아 취약 판정이 불가능했다).
import re


def check(ctx):
    ip_ifaces = ctx.ip_interface_blocks()
    if not ip_ifaces:
        return {"status": "NA", "detail": "IP가 설정된 인터페이스를 찾지 못함", "evidence": ""}
    enabled = [b.splitlines()[0] for b in ip_ifaces if re.search(r"^\s*ip directed-broadcast(?:[ \t]+\S+)?[ \t]*$", b, re.M)]
    if enabled:
        return {
            "status": "VULN",
            "detail": f"ip directed-broadcast 가 명시적으로 허용된 인터페이스 {len(enabled)}개",
            "evidence": ", ".join(enabled),
        }
    missing = [b.splitlines()[0] for b in ip_ifaces if not re.search(r"^\s*no ip directed-broadcast\s*$", b, re.M)]
    if not missing:
        return {"status": "GOOD", "detail": "모든 IP 인터페이스에 no ip directed-broadcast 가 설정되어 있음", "evidence": ""}
    return {
        "status": "MANUAL",
        "detail": f"no ip directed-broadcast 설정이 없는 인터페이스 {len(missing)}개 - IOS 12.0 이상은 기본 차단이나 실제 버전 확인 후 판단 필요",
        "evidence": ", ".join(missing),
    }
