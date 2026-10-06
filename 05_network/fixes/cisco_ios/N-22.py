# N-22 (상) Spoofing 방지 필터링 적용 [Cisco IOS] - 조치 명령어 생성
# checks/cisco_ios/N-22.py: VULN = RFC 6890 특수 용도 대역을 차단하는 ACL을 찾지 못함.
# 어떤 인터페이스가 "경계(외부 연결)" 인터페이스인지는 설정 텍스트만으로 알 수 없으므로, ACL
# 정의만 생성하고 실제 적용(ip access-group ... in)은 경계 인터페이스를 확인한 뒤 수동으로
# 추가하도록 안내한다.
_SPECIAL_NETS = [
    ("0.0.0.0", "0.255.255.255"),
    ("10.0.0.0", "0.255.255.255"),
    ("127.0.0.0", "0.255.255.255"),
    ("169.254.0.0", "0.0.255.255"),
    ("172.16.0.0", "0.15.255.255"),
    ("192.0.2.0", "0.0.0.255"),
    ("192.168.0.0", "0.0.255.255"),
    ("224.0.0.0", "15.255.255.255"),
]
_ACL_NUM = "100"


def generate(ctx):
    cmds = [f"access-list {_ACL_NUM} deny ip {net} {wc} any" for net, wc in _SPECIAL_NETS]
    cmds.append(f"access-list {_ACL_NUM} permit ip any any")
    cmds.append(f"! 주의: 위 {_ACL_NUM}번 ACL을 실제 경계(외부 연결) 인터페이스에 적용할 것 - 예:")
    cmds.append("! interface <경계-인터페이스>")
    cmds.append(f"! ip access-group {_ACL_NUM} in")
    return cmds
