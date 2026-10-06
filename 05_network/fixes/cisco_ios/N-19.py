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
import re

from parsers import cisco_ios as cio

_ACL_NUM = "20"


def generate(ctx):
    lines = ctx.find(r"^snmp-server community (\S+)(?:[ \t]+(RO|RW))?(?:[ \t]+\S+)?[ \t]*$")
    cmds = []
    added_acl_decl = False
    subsumed_by_n18 = False
    for string_, rw in lines:
        if cio.snmp_community_weak(string_):
            subsumed_by_n18 = True
            continue
        # 이미 ACL이 있는 라인인지는 원본 전체 라인으로 재확인(끝에 RO/RW 가 아닌 토큰이 더 있으면 ACL 있음).
        # split()[3:] 로 "snmp-server"/"community"/"<community 문자열>" 3개 토큰을 건너뛰어야 하는데
        # [2:]로 한 칸 덜 건너뛰어 community 문자열 자신이 "ACL 토큰"으로 오인되는 버그가 있었다
        # (문자열 뒤에 RO/RW도 ACL도 없는 가장 흔한 취약 사례에서 전혀 명령을 생성하지 못함 - 실기 테스트로 발견).
        full = ctx.search(rf"^snmp-server community {re.escape(string_)}[ \t]+\S.*$")
        tokens = full.group(0).split()[3:] if full else []
        rest_after_rorw = [t for t in tokens if t not in ("RO", "RW")]
        if rest_after_rorw:
            continue
        if not added_acl_decl:
            cmds.append(f"! 주의: 아래 {_ACL_NUM}번 ACL의 permit 대상을 실제 관리 시스템 IP로 반드시 교체할 것")
            cmds.append(f"access-list {_ACL_NUM} permit <관리-시스템-IP> <wildcard mask>")
            added_acl_decl = True
        cmds.append(f"no snmp-server community {string_}")
        cmds.append(f"snmp-server community {string_} RO {_ACL_NUM}")
    if not cmds and subsumed_by_n18:
        cmds.append("! 이 항목의 조치 대상 라인은 N-18(문자열 복잡성) 조치 명령에 ACL과 함께 이미 포함되어 있음 - 위 N-18 블록 참고")
    return cmds
