# N-20 (상) SNMP Community 권한 설정 [Cisco IOS] - 조치 명령어 생성
# checks/cisco_ios/N-20.py: VULN = 읽기-쓰기(RW, 또는 RO/RW 미지정 시 기본값인 RW) 권한의
# SNMP community 설정 존재. 기존 community 문자열/ACL은 유지하고 권한만 RO로 재발급한다.
# 주의: ACL이 없는 라인은 건드리지 않는다 - 그런 라인은 N-19(ACL 설정)도 함께 VULN이라
# fixes/cisco_ios/N-19.py 가 ACL+RO를 한 번에 반영하도록 전담한다. 여기서 ACL 없는 라인까지
# "RO만" 재발급하면 N-19가 뒤에 추가한 ACL을 이 명령이 다시 지워버리는(또는 그 반대) 상호
# 덮어쓰기 버그가 있었다(생성된 스크립트를 순서대로 적용해보는 실기 테스트로 발견) - 이 책임
# 분리로 해결했다. ACL이 이미 있는데 RW인 라인(N-19는 GOOD, N-20만 VULN인 경우)만 처리한다.
# 문자열 자체가 약한(N-18 VULN) 라인도 N-18이 전담하므로 건너뛴다(같은 이유).
from parsers import cisco_ios as cio


def generate(ctx):
    lines = ctx.find(r"^snmp-server community (\S+)(?:[ \t]+(RO|RW))?((?:[ \t]+\S+)?)[ \t]*$")
    cmds = []
    subsumed = False
    for string_, rw, acl_part in lines:
        is_rw = rw == "RW" or rw == ""
        if not is_rw:
            continue
        if not acl_part.strip() or cio.snmp_community_weak(string_):
            subsumed = True  # ACL 없음(N-19) 또는 문자열 약함(N-18) - 둘 다 다른 항목이 RO까지 함께 반영
            continue
        cmds.append(f"no snmp-server community {string_}")
        cmds.append(f"snmp-server community {string_} RO{acl_part}".rstrip())
    if not cmds and subsumed:
        cmds.append("! 이 항목의 조치 대상 라인은 N-18(문자열 복잡성)/N-19(ACL) 조치 명령에 RO 권한과 함께 이미 포함되어 있음 - 위 블록 참고")
    return cmds
