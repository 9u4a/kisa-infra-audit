# N-22 (상) Spoofing 방지 필터링 적용 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = 경계 라우터/보안장비에 스푸핑 방지 필터링 적용 / 취약 = 미적용
# 자동화 범위: 어떤 인터페이스가 "경계(외부 연결)" 인터페이스인지 설정 텍스트만으로 단정할 수
# 없으므로, RFC 6890 특수 용도 대역을 차단하는 ACL 존재 여부까지만 자동 확인하고 실제 적용
# 위치(인터페이스)는 MANUAL로 안내한다.
_SPECIAL_NETS = ["0.0.0.0", "10.0.0.0", "127.0.0.0", "169.254.0.0", "172.16.0.0", "192.0.2.0", "192.168.0.0", "224.0.0.0"]


def check(ctx):
    denies = ctx.find(r"^access-list \d+ deny ip (\d{1,3}(?:\.\d{1,3}){3})")
    matched = [n for n in _SPECIAL_NETS if n in denies]
    evidence = "탐지된 특수용도 대역 차단 ACL: " + ", ".join(matched) if matched else "없음"
    if len(matched) >= 4:
        return {"status": "MANUAL", "detail": f"특수 용도 대역 차단 ACL이 {len(matched)}개 대역에서 발견됨 - 경계 인터페이스에 실제 적용(ip access-group)되어 있는지 수동 확인 필요", "evidence": evidence}
    return {"status": "VULN", "detail": "RFC 6890 특수 용도 대역(사설/루프백 등)을 차단하는 스푸핑 방지 ACL을 찾지 못함", "evidence": evidence}
