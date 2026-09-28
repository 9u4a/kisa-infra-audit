# N-05 (중) 사용자·명령어별 권한 설정 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = 업무에 맞게 계정의 권한이 차등 부여된 경우
#                        취약 = 차등 부여되지 않은 경우 (※ 관리자 1명만 운영하는 경우는 해당 없음)
# "업무에 맞게"는 조직 구조를 알아야 판단 가능 - 완전 자동 판정 불가. 계정별 권한 수준(privilege)
# 설정 현황을 증적으로 제공한다.
def check(ctx):
    users = ctx.find(r"^username (\S+) privilege (\d+)")
    priv_cmds = ctx.find(r"^privilege exec level (\d+) (.+)$")
    evidence = "계정별 권한:\n" + "\n".join(f"{u} privilege {p}" for u, p in users)
    evidence += "\n명령어별 권한:\n" + "\n".join(f"level {lvl}: {cmd}" for lvl, cmd in priv_cmds)

    if not users:
        return {"status": "MANUAL", "detail": "계정별 privilege 수준 설정을 찾지 못함 - 계정별 권한 차등 부여 여부 수동 확인 필요(관리자 1인 운영 시 해당없음)", "evidence": evidence}
    levels = {int(p) for _, p in users}
    if len(levels) <= 1 and 15 in levels:
        return {"status": "MANUAL", "detail": "모든 계정이 최고 권한(15)만 사용 중 - 업무별 차등 부여가 필요한지 수동 확인 필요", "evidence": evidence}
    return {"status": "MANUAL", "detail": "계정별로 서로 다른 privilege 수준이 설정되어 있음 - 실제 업무에 맞게 부여되었는지는 수동 확인 필요", "evidence": evidence}
