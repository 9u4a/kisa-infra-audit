# N-01 (상) 비밀번호 설정 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = 기본 비밀번호를 변경한 경우
#                        취약 = 기본 비밀번호를 변경하지 않거나 비밀번호를 설정하지 않은 경우
# 자동화 범위: 오프라인 설정 텍스트만으로는 "기본 비밀번호 그대로 방치"를 직접 확인할 수 없으므로,
# 대리 지표로 enable 비밀번호와 VTY/콘솔 라인 비밀번호(또는 login local)가 아예 설정되어 있지
# 않은 경우만 명확한 취약으로 판단한다.
import re


def check(ctx):
    has_enable = ctx.has(r"^enable (secret|password) \S+")
    vty_blocks = ctx.line_block_text("vty")
    con_blocks = ctx.line_block_text("con")

    def line_authenticated(block_text):
        if re.search(r"^\s*password \S+", block_text, re.M):
            return True
        if re.search(r"^\s*login local\s*$", block_text, re.M):
            return True
        if re.search(r"^\s*login authentication \S+", block_text, re.M):
            return True
        return False

    vty_ok = any(line_authenticated(b) for b in vty_blocks) if vty_blocks else False
    con_ok = any(line_authenticated(b) for b in con_blocks) if con_blocks else True  # 콘솔 미설정은 물리 접근 전제

    evidence = f"enable 비밀번호 설정={has_enable}\nVTY 인증 설정={vty_ok}\n" + "\n---\n".join(vty_blocks)

    if not has_enable:
        return {"status": "VULN", "detail": "enable 비밀번호(enable secret/password)가 설정되어 있지 않음", "evidence": evidence}
    if vty_blocks and not vty_ok:
        return {"status": "VULN", "detail": "VTY 라인에 비밀번호/인증 설정이 없음", "evidence": evidence}
    return {"status": "GOOD", "detail": "enable 비밀번호와 VTY 인증이 설정되어 있음(실제 값이 기본값과 다른지는 별도 확인 필요)", "evidence": evidence}
