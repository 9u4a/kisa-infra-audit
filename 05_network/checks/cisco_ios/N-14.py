# N-14 (중) 정책에 따른 로깅 설정 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = 로그 기록 정책에 따라 로깅 설정 / 취약 = 정책 미수립·설정 미흡
# "정책에 따라"는 조직의 로그 기록 정책 문서를 알아야 판단 가능 - 항상 MANUAL. 로깅 관련 설정
# 존재 여부(buffered/trap/console 등)를 증적으로 제공한다.
def check(ctx):
    logging_lines = [l for l in ctx.lines if l.startswith("logging ") or l == "no logging console"]
    evidence = "\n".join(logging_lines)
    if not logging_lines:
        return {"status": "VULN", "detail": "logging 관련 설정이 전혀 없음", "evidence": evidence}
    return {"status": "MANUAL", "detail": "로깅 설정이 일부 존재함 - 기관의 로그 기록 정책에 맞게 구성되었는지 수동 확인 필요", "evidence": evidence}
