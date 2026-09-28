# N-38 (중) mask-reply 차단 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = mask-reply 차단 / 취약 = 미차단
# 참고(가이드 원문 명시): "기본적으로 ip mask-reply 명령은 비활성화 상태이기 때문에 구성 내용에서
# no ip mask-reply 명령이 표시되지 않음" - 가이드가 직접 명시한 기본값이므로, IP 인터페이스에
# 명시적 활성화(ip mask-reply)만 없으면 양호로 판단한다.
import re


def check(ctx):
    ip_ifaces = ctx.ip_interface_blocks()
    if not ip_ifaces:
        return {"status": "NA", "detail": "IP가 설정된 인터페이스를 찾지 못함", "evidence": ""}
    enabled = [b.splitlines()[0] for b in ip_ifaces if re.search(r"^\s*ip mask-reply\s*$", b, re.M)]
    if enabled:
        return {"status": "VULN", "detail": f"ip mask-reply 가 명시적으로 활성화된 인터페이스 존재: {enabled}", "evidence": ", ".join(enabled)}
    return {"status": "GOOD", "detail": "mask-reply 활성화 설정이 없음(가이드 원문 기준 기본 차단 상태)", "evidence": ""}
