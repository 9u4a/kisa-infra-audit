# N-17 (상) SNMP 서비스 확인 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = 사용하지 않는 SNMP 서비스를 비활성화 / 취약 = 비활성화하지 않음
# 자동화 범위: snmp-server 설정이 전혀 없으면(=비활성화) 양호. 설정이 있으면 "실제로 필요해서
# 쓰는 것"인지 판단할 수 없으므로 MANUAL 로 남기고 N-18~20에서 세부 설정을 점검하도록 안내한다.
def check(ctx):
    snmp_lines = [l for l in ctx.lines if l.startswith("snmp-server")]
    if not snmp_lines:
        return {"status": "GOOD", "detail": "snmp-server 설정이 없어 SNMP 서비스가 비활성화 상태임", "evidence": ""}
    return {"status": "MANUAL", "detail": "SNMP 서비스가 사용 중임 - 실제 업무상 필요한지, N-18~N-20 세부 설정이 적절한지 수동 확인 필요", "evidence": "\n".join(snmp_lines)}
