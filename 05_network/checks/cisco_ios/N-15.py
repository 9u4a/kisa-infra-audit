# N-15 (중) NTP 및 시각 동기화 설정 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = NTP 서버를 통한 시간 동기화 설정 / 취약 = 미설정
def check(ctx):
    m = ctx.search(r"^ntp server (\S+)")
    if m:
        return {"status": "GOOD", "detail": f"NTP 서버가 설정되어 있음({m.group(1)})", "evidence": m.group(0)}
    return {"status": "VULN", "detail": "ntp server 설정이 없음", "evidence": ""}
