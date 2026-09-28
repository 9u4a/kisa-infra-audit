# N-27 (중) 웹 서비스 차단 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = 불필요한 웹 서비스 차단 또는 허용 IP만 접속 가능 / 취약 = 미차단
def check(ctx):
    http_on = ctx.has(r"^ip http server\s*$")
    https_on = ctx.has(r"^ip http secure-server\s*$")
    if not http_on and not https_on:
        return {"status": "GOOD", "detail": "ip http server/secure-server 가 모두 비활성화되어 있음", "evidence": ""}
    m = ctx.search(r"^ip http access-class (\S+)")
    evidence = f"http={http_on}, https={https_on}, access-class={m.group(1) if m else '없음'}"
    if m:
        return {"status": "GOOD", "detail": "웹 서비스가 활성화되어 있으나 접근 IP가 access-class로 제한되어 있음", "evidence": evidence}
    return {"status": "VULN", "detail": "웹 서비스(http/https)가 활성화되어 있고 접근 제한(access-class)이 없음", "evidence": evidence}
