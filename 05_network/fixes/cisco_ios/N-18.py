# N-18 (상) SNMP Community String 복잡성 설정 [Cisco IOS] - 조치 명령어 생성
# checks/cisco_ios/N-18.py: VULN = public/private 기본값 또는 복잡성 기준(3종류 이상 조합,
# 8자리 이상) 미달 Community String 존재. 기존 문자열은 평문으로 남기지 않는 증적 원칙과 달리,
# 이 스크립트 자체가 실제 적용 대상이라 새로 생성한 문자열을 담아야 한다(parsers/cisco_ios.py
# gen_secret 참고) - 적용 후 안전하게 별도 보관하고 이 스크립트 파일은 삭제할 것.
# 주의(N-19/N-20과의 상호작용): 문자열이 약해서 여기서 새 문자열로 재발급하는 라인은, 같은 라인이
# N-19(ACL 없음)/N-20(RW) 로도 동시에 VULN일 수 있다. 세 항목이 각자 독립적으로 "원본 설정"만
# 보고 재발급 명령을 만들면 나중에 실행되는 명령이 앞선 명령을 덮어써 결과적으로 약한 문자열이나
# RW 권한이 되살아나는 문제가 있었다(생성된 스크립트를 순서대로 적용해보는 실기 테스트로 발견).
# 그래서 문자열이 약한 라인은 여기서 새 문자열 + RO + (없으면) ACL placeholder까지 한 번에
# 반영해 전담하고, fixes/cisco_ios/N-19.py・N-20.py 는 parsers.cisco_ios.snmp_community_weak() 로
# 이 라인을 건너뛴다.
# 조치 후속 F-R7: 옛 정규식(`<string> [RO|RW] [acl]$`)은 view·ipv6 토큰이 있는 줄을 놓쳐, 그런 줄의 약한
# 문자열은 N-18 도 N-19/N-20 도 명령을 만들지 않았다. 진단과 같은 parse_snmp_community 로 해석하고,
# 재발급할 때 view·ipv6 ACL 을 그대로 유지한다.
from parsers import cisco_ios as cio

_ACL_NUM = "20"


def generate(ctx):
    cmds = []
    added_acl_decl = False
    for info in cio.snmp_communities(ctx):
        old = info["string"]
        if not cio.snmp_community_weak(old):
            continue
        new = cio.gen_secret()
        acl = info["acl"]
        if not acl:
            if not added_acl_decl:
                cmds.append(f"! 주의: 아래 {_ACL_NUM}번 ACL의 permit 대상을 실제 관리 시스템 IP로 반드시 교체할 것(N-19 겸용)")
                cmds.append(f"access-list {_ACL_NUM} permit <관리-시스템-IP> <wildcard mask>")
                added_acl_decl = True
            acl = _ACL_NUM
        cmds.append(f"no snmp-server community {old}")
        cmds.append(cio.build_snmp_community(new, "RO", info["view"], info["ipv6_acl"], acl))
    return cmds
