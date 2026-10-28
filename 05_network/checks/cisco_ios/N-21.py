# N-21 (상) TFTP 서비스 차단 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = TFTP 서비스 차단(또는 ACL로 허용 시스템만 제한) / 취약 = 미차단
# 문법: tftp-server <파일> [alias <이름>] [<ACL 번호>]
# 예전에는 "토큰이 3개 이상이면 ACL 있음"으로 봐서 `alias` 만 붙은 줄을 거짓 GOOD 으로 판정했다(진단 검수 D-R11).
# 여러 줄이면 하나라도 ACL 이 없으면 취약.
def check(ctx):
    lines = [l.rstrip() for l in ctx.lines if l.startswith("tftp-server ")]
    if not lines:
        return {"status": "GOOD", "detail": "tftp-server 설정이 없어 TFTP 서비스가 구동되지 않음", "evidence": ""}
    no_acl = []
    for line in lines:
        rest = line.split()[2:]  # 'tftp-server' '<파일>' 건너뜀
        if rest[:1] == ["alias"]:
            rest = rest[2:]      # 'alias' '<이름>' 건너뜀
        if not rest:
            no_acl.append(line)
    evidence = "\n".join(lines)
    if no_acl:
        return {"status": "VULN", "detail": f"TFTP 서비스가 ACL 제한 없이 구동 중임({len(no_acl)}건)", "evidence": evidence}
    return {"status": "GOOD", "detail": "TFTP 서비스가 구동 중이나 ACL로 접근이 제한되어 있음", "evidence": evidence}
