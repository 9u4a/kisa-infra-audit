# N-01 (상) 비밀번호 설정 [Cisco IOS] - 조치 명령어 생성
# checks/cisco_ios/N-01.py 가 VULN 으로 판정한 두 경우(enable 비밀번호 없음 / VTY 인증 없음)에
# 대해 새 비밀번호를 적용하는 명령을 생성한다. 실제 비밀번호 값은 알 수 없으므로(D-01/WEB-02와
# 동일 원칙) 무작위로 강력한 값을 새로 생성해 스크립트에 담는다 - 적용 후 반드시 별도로 안전하게
# 기록하고 이 스크립트 파일은 삭제할 것.
import re

from parsers import cisco_ios as cio


def generate(ctx):
    cmds = []
    if not ctx.has(r"^enable (secret|password) \S+"):
        cmds.append(f"enable secret {cio.gen_secret()}")
    vty_blocks = ctx.line_block_text("vty")

    def authenticated(block_text):
        return bool(
            re.search(r"^\s*password \S+", block_text, re.M)
            or re.search(r"^\s*login local\s*$", block_text, re.M)
            or re.search(r"^\s*login authentication \S+", block_text, re.M)
        )

    if vty_blocks and not any(authenticated(b) for b in vty_blocks):
        for b in vty_blocks:
            cmds.append(f"line {cio.iface_name(b)}")
            cmds.append(f"password {cio.gen_secret()}")
            cmds.append("login")
            cmds.append("exit")
    return cmds
