# N-03 (상) 암호화된 비밀번호 사용 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = 비밀번호 암호화 설정 적용 / 취약 = 미적용
# enable secret(일방향 해시) 또는 service password-encryption(양방향 암호화) 중 하나라도
# 적용되어 있으면 양호로 본다. enable password 만 평문으로 쓰고 있으면 취약.
def check(ctx):
    has_enable_secret = ctx.has(r"^enable secret \S+")
    has_enable_password_only = ctx.has(r"^enable password \S+") and not has_enable_secret
    has_pw_encryption = ctx.has(r"^service password-encryption\s*$")
    has_username_secret = ctx.has(r"^username \S+ secret \S+")

    evidence = (
        f"enable secret={has_enable_secret}, enable password(평문 가능성)={has_enable_password_only}, "
        f"service password-encryption={has_pw_encryption}, username ... secret={has_username_secret}"
    )

    if has_enable_secret or has_pw_encryption:
        return {"status": "GOOD", "detail": "enable secret 또는 service password-encryption 이 적용되어 있음", "evidence": evidence}
    if has_enable_password_only:
        return {"status": "VULN", "detail": "enable password 만 사용 중이며 암호화 설정(enable secret/service password-encryption)이 없음", "evidence": evidence}
    return {"status": "MANUAL", "detail": "enable 비밀번호 설정을 찾지 못함 - N-01과 함께 수동 확인 필요", "evidence": evidence}
