# N-06 (상) VTY 접근(ACL) 설정 [Cisco IOS] - 조치 명령어 생성
# checks/cisco_ios/N-06.py: VULN = VTY 라인에 access-class(ACL) 미설정. ACL 허용 대상(관리자
# PC/대역)은 설정 텍스트만으로 알 수 없으므로 자리표시자(placeholder)를 반드시 실제 대역으로
# 바꾼 뒤 적용해야 한다 - placeholder 그대로 적용하면 VTY 접근이 전부 막혀 잠길 수 있다.
from parsers import cisco_ios as cio

_ACL_NUM = "10"


def generate(ctx):
    vty_blocks = ctx.line_block_text("vty")
    missing = [b for b in vty_blocks if "access-class" not in b]
    if not missing:
        return []
    cmds = [
        f"! 주의: 아래 {_ACL_NUM}번 ACL의 permit 대상을 실제 관리자 PC/관리망 대역으로 반드시 교체할 것",
        f"! (placeholder 그대로 적용 시 VTY 접근이 전부 차단되어 원격 관리가 불가능해질 수 있음)",
        f"access-list {_ACL_NUM} permit <관리자-PC-또는-관리망-대역> <wildcard mask>",
    ]
    for b in missing:
        cmds.append(f"line {cio.iface_name(b)}")
        cmds.append(f"access-class {_ACL_NUM} in")
        cmds.append("exit")
    return cmds
