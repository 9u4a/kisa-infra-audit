# N-24 (상) 사용하지 않는 인터페이스 비활성화 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = 사용하지 않는 인터페이스가 비활성화(shutdown)됨 / 취약 = 미비활성화
# 자동화 범위: "사용하지 않는다"는 것은 설정 텍스트만으로 알 수 없다(IP가 없어도 스위치 포트로
# 정상 사용 중일 수 있음). IP 미설정 + shutdown 미설정인 인터페이스 목록을 증적으로 제공해 수동
# 검토를 안내한다.
import re


def check(ctx):
    candidates = []
    for block in ctx.interface_blocks:
        body = "\n".join(block)
        name = block[0].split()[1] if len(block[0].split()) > 1 else block[0]
        has_ip = bool(re.search(r"^\s*ip address \d", body, re.M))
        is_shutdown = bool(re.search(r"^\s*shutdown\s*$", body, re.M))
        if not has_ip and not is_shutdown:
            candidates.append(name)
    if not candidates:
        return {"status": "GOOD", "detail": "IP 미설정 상태에서 비활성화도 안 된 인터페이스를 찾지 못함", "evidence": ""}
    return {
        "status": "MANUAL",
        "detail": f"IP가 설정되지 않았고 shutdown도 되어 있지 않은 인터페이스 {len(candidates)}개 발견 - 실제 미사용 여부를 수동 확인 후 비활성화 필요",
        "evidence": ", ".join(candidates),
    }
