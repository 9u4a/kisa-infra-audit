# N-09 (중) 불필요한 보조 입출력 포트 사용 금지 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = 불필요한 포트/인터페이스 사용 제한 / 취약 = 제한하지 않음
# 자동화 범위: AUX 포트 차단 여부만 텍스트로 확인 가능(어떤 인터페이스가 "불필요"한지는 설정
# 파일만으로 알 수 없음). AUX 포트가 아예 설정되지 않은 경우는 장비에 AUX가 없거나 기본 상태일
# 수 있어 MANUAL 로 남긴다.
import re


def check(ctx):
    aux_blocks = ctx.line_block_text("aux")
    if not aux_blocks:
        return {"status": "MANUAL", "detail": "line aux 설정을 찾지 못함 - AUX 포트 존재 여부와 차단 상태를 수동 확인 필요", "evidence": ""}
    evidence = "\n---\n".join(aux_blocks)
    blocked = all(
        re.search(r"^\s*transport input none", b, re.M) or re.search(r"^\s*no exec\s*$", b, re.M)
        for b in aux_blocks
    )
    if blocked:
        return {"status": "GOOD", "detail": "AUX 포트가 차단되어 있음(transport input none / no exec)", "evidence": evidence}
    return {"status": "VULN", "detail": "AUX 포트가 차단되어 있지 않음", "evidence": evidence}
