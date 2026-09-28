# N-21 (상) TFTP 서비스 차단 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = TFTP 서비스 차단(또는 ACL로 허용 시스템만 제한) / 취약 = 미차단
def check(ctx):
    m = ctx.search(r"^tftp-server\b.*$")
    if not m:
        return {"status": "GOOD", "detail": "tftp-server 설정이 없어 TFTP 서비스가 구동되지 않음", "evidence": ""}
    tokens = m.group(0).split()
    has_acl = len(tokens) >= 3  # tftp-server <flash:...> <ACL 번호/이름> 형태
    if has_acl:
        return {"status": "GOOD", "detail": "TFTP 서비스가 구동 중이나 ACL로 접근이 제한되어 있음", "evidence": m.group(0)}
    return {"status": "VULN", "detail": "TFTP 서비스가 ACL 제한 없이 구동 중임", "evidence": m.group(0)}
