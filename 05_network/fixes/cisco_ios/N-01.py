# N-01 (상) 비밀번호 설정 [Cisco IOS] - 조치 명령어 생성
# 영향: enable·VTY 비밀번호(AAA 인증 목록) 교체 — 기존 비밀번호·무인증으로 접속하던 관리자·자동화 도구의 다음 접속 실패
# checks/cisco_ios/N-01.py 가 VULN 으로 판정한 경우(enable 비밀번호 없음 / VTY 인증 없음)에
# 대해 새 비밀번호를 적용하는 명령을 생성한다. 실제 비밀번호 값은 알 수 없으므로(D-01/WEB-02와
# 동일 원칙) 무작위로 강력한 값을 새로 생성해 스크립트에 담는다 - 적용 후 반드시 별도로 안전하게
# 기록하고 이 스크립트 파일은 삭제할 것.
# 외부 검수 A11: 진단과 같은 cio.vty_line_authenticated 로 대상 라인을 고른다(예전에는 진단은 all(), 조치는 any() 라
# 일부 라인만 무인증이면 명령을 만들지 않았다). aaa new-model 장비는 라인 password 가 쓰이지 않으므로, 방식이 none
# 뿐인 AAA 목록을 local 인증으로 바꾸고, 그런 목록을 지정한 라인은 default 목록을 쓰게 한다.
from parsers import cisco_ios as cio


def generate(ctx):
    cmds = []
    if not ctx.has(r"^enable (secret|password) \S+"):
        cmds.append(f"enable secret {cio.gen_secret()}")
    open_blocks = [b for b in ctx.line_block_text("vty") if not cio.vty_line_authenticated(ctx, b)]
    if not open_blocks:
        return cmds

    if ctx.has(r"^aaa new-model\s*$"):
        lists = cio.aaa_login_lists(ctx)
        if not ctx.has(r"^username \S+ .*\bsecret\b"):
            cmds.append("! 주의: local 인증용 계정이 없어 새로 만든다 - 계정명/비밀번호를 안전하게 기록할 것")
            cmds.append(f"username netadmin privilege 15 secret {cio.gen_secret()}")
        if not cio.aaa_methods_authenticate(lists.get("default")):
            cmds.append("! default 로그인 목록이 없거나 none 뿐이라 인증 없이 접속된다 - local 계정 인증으로 바꾼다")
            cmds.append("aaa authentication login default local")
        for b in open_blocks:
            cmds.append(f"line {cio.iface_name(b)}")
            cmds.append("login authentication default")
            cmds.append("exit")
        return cmds

    for b in open_blocks:
        cmds.append(f"line {cio.iface_name(b)}")
        cmds.append(f"password {cio.gen_secret()}")
        cmds.append("login")
        cmds.append("exit")
    return cmds
