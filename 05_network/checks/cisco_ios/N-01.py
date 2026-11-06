# N-01 (상) 비밀번호 설정 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = 기본 비밀번호를 변경한 경우
#                        취약 = 기본 비밀번호를 변경하지 않거나 비밀번호를 설정하지 않은 경우
# 자동화 범위: 오프라인 설정 텍스트만으로는 "기본 비밀번호 그대로 방치"를 직접 확인할 수 없으므로,
# 대리 지표로 enable 비밀번호와 VTY/콘솔 라인 비밀번호(또는 login local)가 아예 설정되어 있지
# 않은 경우만 명확한 취약으로 판단한다.
from parsers import cisco_ios as cio


def check(ctx):
    has_enable = ctx.has(r"^enable (secret|password) \S+")
    vty_blocks = ctx.line_block_text("vty")

    # aaa new-model + "aaa authentication login default ..." 이면 login authentication 을 따로 지정하지 않은
    # 라인도 default 목록으로 인증한다(실무 적용 검증 P-11). 단, 방식이 none 뿐인 목록(default none 등)은 무인증이다 -
    # P-11 수정 뒤 `aaa authentication login default none` 도 GOOD 이던 문제(외부 검수 A11). 판정은 fix 와 같은
    # cio.vty_line_authenticated 로 한다.
    aaa_default = cio.aaa_login_lists(ctx).get("default") if ctx.has(r"^aaa new-model\s*$") else None

    # 예전에는 any() 라 "line vty 0 4" 만 인증하고 "line vty 5 15" 는 열어둔 장비가 GOOD 이었다(진단 검수 D-R10) -
    # 모든 VTY 블록이 인증을 요구해야 양호다. 콘솔 미설정은 물리 접근 전제라 판정에서 제외(기존과 동일).
    vty_ok = all(cio.vty_line_authenticated(ctx, b) for b in vty_blocks) if vty_blocks else False

    # VTY 블록의 password 값(평문·type 7)은 증적에 남기지 않는다(진단 검수 D-R4, S5).
    evidence = f"enable 비밀번호 설정={has_enable}\nVTY 인증 설정={vty_ok}\nAAA 로그인 default 목록={' '.join(aaa_default) if aaa_default else '없음'}\n" + cio.mask_secrets("\n---\n".join(vty_blocks))

    if not has_enable:
        return {"status": "VULN", "detail": "enable 비밀번호(enable secret/password)가 설정되어 있지 않음", "evidence": evidence}
    if vty_blocks and not vty_ok:
        return {"status": "VULN", "detail": "비밀번호/인증 설정이 없는(또는 no login, AAA 방식이 none 뿐인) VTY 라인이 있음", "evidence": evidence}
    return {"status": "GOOD", "detail": "enable 비밀번호와 VTY 인증이 설정되어 있음(실제 값이 기본값과 다른지는 별도 확인 필요)", "evidence": evidence}
