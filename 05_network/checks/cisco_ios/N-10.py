# N-10 (중) 로그인 시 경고 메시지 설정 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = 경고 메시지 설정 / 취약 = 미설정 또는 시스템 정보 노출
def check(ctx):
    has_banner = ctx.has(r"^banner (motd|login|exec) ")
    if has_banner:
        return {"status": "MANUAL", "detail": "배너(motd/login/exec)가 설정되어 있음 - 문구에 시스템 정보 노출이 없고 경고 문구가 적절한지 수동 확인 필요", "evidence": ""}
    return {"status": "VULN", "detail": "banner motd/login/exec 설정이 없음", "evidence": ""}
