# N-19 (상) SNMP ACL 설정 [Cisco IOS] - 조치 명령어 생성
# checks/cisco_ios/N-19.py: VULN = ACL이 지정되지 않은 SNMP community 설정 존재. 허용할
# 관리 시스템 IP는 설정 텍스트만으로 알 수 없으므로 자리표시자를 반드시 교체해야 한다. 기존
# community 문자열은 그대로 유지(재발급)하면서 ACL을 추가한다.
# 주의(N-20과의 상호작용): ACL이 없는 라인을 재발급할 때는 권한을 항상 RO로 강제한다(원래
# RW였더라도). 같은 community 라인이 N-19/N-20 둘 다 VULN(ACL도 없고 RW)인 경우, 두 항목의
# 명령이 같은 스크립트에 함께 들어가는데, 서로 독립적으로 "원본 설정"만 보고 재발급 명령을
# 만들면 나중에 실행되는 쪽이 앞선 변경을 덮어써버리는 문제가 있었다(예: N-19가 ACL을 붙여도
# N-20이 그걸 모른 채 ACL 없이 다시 재발급 - 또는 그 반대 - 해서 결과적으로 최종 상태에 둘 중
# 하나만 반영됨, 생성된 스크립트를 그대로 적용해보는 실기 테스트로 발견). 이 라인들은 N-19가
# 전담해 ACL+RO를 한 번에 반영하고, fixes/cisco_ios/N-20.py 는 "이미 ACL이 있는데 RW인" 라인만
# 처리하도록 책임을 분리해 해결했다. 문자열 자체가 약한(N-18 VULN) 라인은 N-18이 새 문자열과
# 함께 ACL+RO까지 한 번에 반영하므로 여기서는 건너뛴다(그렇지 않으면 N-18이 재발급한 새
# 문자열을 모른 채 옛 문자열로 다시 재발급해 약한 문자열이 되살아난다).
# 조치 후속 F-R7: 옛 정규식(`<string> [RO|RW] [acl]$`)은 view·ipv6 토큰이 있는 줄을 놓쳐(진단은 VULN 인데) 명령을
# 만들지 못하고 수동 안내로 빠졌다. 진단과 같은 parse_snmp_community 로 해석하고, 재발급할 때 view·ipv6 ACL 을 유지한다.
# IPv4 ACL 이 없으면(ipv6 ACL 만 있어도) 진단과 같이 대상으로 본다.
from parsers import cisco_ios as cio

_ACL_NUM = "20"


def generate(ctx):
    cmds = []
    added_acl_decl = False
    subsumed_by_n18 = False
    for info in cio.snmp_communities(ctx):
        string_ = info["string"]
        if cio.snmp_community_weak(string_):
            subsumed_by_n18 = True
            continue
        if info["acl"]:
            continue
        if not added_acl_decl:
            cmds.append(f"! 주의: 아래 {_ACL_NUM}번 ACL의 permit 대상을 실제 관리 시스템 IP로 반드시 교체할 것")
            cmds.append(f"access-list {_ACL_NUM} permit <관리-시스템-IP> <wildcard mask>")
            added_acl_decl = True
        cmds.append(f"no snmp-server community {string_}")
        cmds.append(cio.build_snmp_community(string_, "RO", info["view"], info["ipv6_acl"], _ACL_NUM))
    if not cmds and subsumed_by_n18:
        cmds.append("! 이 항목의 조치 대상 라인은 N-18(문자열 복잡성) 조치 명령에 ACL과 함께 이미 포함되어 있음 - 위 N-18 블록 참고")
    return cmds
